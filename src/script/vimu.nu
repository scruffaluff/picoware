#!/usr/bin/env nu
#
# Convenience script for QEMU and Virsh.

use std/log

def ask-password [] {
    let password = input --suppress-output "Password: "
    print ""
    let confirm = input --suppress-output "Confirm password: "
    print ""

    if $password == $confirm {
        $password
    } else {
        print --stderr "error: Passwords do not match."
        ask-password
    }
}

# Generate cloud init data.
def cloud-init [domain: string username: string password: string] {
    let pub_key = open --raw $"(path-config)/key.pub" | str trim
    let content = $"
#cloud-config

hostname: '($domain)'
preserve_hostname: false
users:
  - doas: [permit nopass ($username)]
    lock_passwd: false
    name: '($username)'
    plain_text_passwd: '($password)'
    ssh_authorized_keys:
      - '($pub_key)'
    sudo: ALL=\(ALL\) NOPASSWD:ALL
"
    | str trim --left

    let path = mktemp --tmpdir --suffix .yaml
    $content | save --force $path
    $path
}

# Create application desktop entry.
def create-app [domain: string] {
    let config = path-config
    let home = path-home
    let title = $domain | str capitalize

    match $nu.os-info.name {
        "macos" => {
            let dest = $"($home)/Applications/($title).app/Contents"
            mkdir $"($dest)/MacOS" $"($dest)/Resources"
            cp $"($config)/icon.icns" $"($dest)/Resources/icon.icns"
            create-entry $domain $"($dest)/MacOS/main.sh"

            (
                $"
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleDisplayName</key>
  <string>($title)</string>
  <key>CFBundleExecutable</key>
  <string>main.sh</string>
  <key>CFBundleIconFile</key>
  <string>icon.icns</string>
  <key>CFBundleIdentifier</key>
  <string>com.scruffaluff.vimu-($domain)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>($domain)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CSResourcesFileMapped</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>10.13</string>
  <key>LSRequiresCarbon</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
"
                | str trim
                | save --force $"($dest)/Info.plist"
            )
        }
        "windows" => {
            error make { msg: "Windows application is not yet supported." }
        }
        _ => {
            let dest = $"($home)/.local/share/applications"
            mkdir $dest
            (
                $"
[Desktop Entry]
Exec=vimu gui ($domain)
Icon=($config)/icon.svg
Name=($title)
StartupWMClass=virt-viewer
Terminal=false
Type=Application
Version=1.0
"
                | str trim --left
                | save --force $"($dest)/($domain).desktop"
            )
        }
    }
}

# Create application entrypoint.
def create-entry [domain: string path: path] {
    const folder = path self | path dirname
    $"
#!/usr/bin/env sh
set -eu

export PATH=\"($folder):${PATH}\"
exec vimu gui ($domain)
"
    | str trim --left | save --force $path
    chmod +rx $path
}

# Create SSH key.
def create-key [] {
    let config = path-config
    if not ($"($config)/key" | path exists) {
        ssh-keygen -N '' -q -f $"($config)/key" -t ed25519 -C vimu
        if $nu.os-info.name != "windows" {
            chmod 600 $"($config)/key" $"($config)/key.pub"
        }
    }
    $"($config)/key"
}

# Find command to elevate as super user.
def find-super [] {
    if (is-admin) {
        ""
    } else if $nu.os-info.name == "windows" {
        error make { msg: 
"System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
"       }
    } else if (which doas | is-not-empty) {
        "doas"
    } else if (which sudo | is-not-empty) {
        "sudo"
    } else {
        error make { msg: "Unable to find a command for super user elevation." }
    }
}

# Create a virtual machine from an ISO disk.
def --wrapped install-cdrom [
    domain: string osinfo: string cdrom: path ...args: string
] {
    let home = path-home
    let params = match $nu.os-info.name {
        "linux" => [--cpu host-passthrough --graphics spice --virt-type kvm]
        "macos" => [--graphics vnc]
        _ => [--cpu host-passthrough --graphics vnc]
    }
    let disk = $"(path-libvirt)/cdroms/($domain).iso"
    cp $cdrom $disk

    (
        virt-install
        --arch $nu.os-info.arch
        --cdrom $disk
        --disk bus=virtio,format=qcow2,size=64
        --memory 8192
        --name $domain
        --osinfo $osinfo
        --vcpus 4
        ...$params
        ...$args
    )
}

# Create a virtual machine from a qcow2 disk.
def --wrapped install-disk [
    name: string osinfo: string image: path extension: string ...args: string
] {
    let params = match $nu.os-info.name {
        "linux" => [--cpu host-passthrough --graphics spice --virt-type kvm]
        "macos" => [--graphics vnc]
        _ => [--cpu host-passthrough --graphics vnc]
    }

    print "Create user account for virtual machine."
    let username = $env.VIMU_USERNAME? | default { input "Username: " }
    let password = $env.VIMU_PASSWORD? | default { ask-password }
    let user_data = cloud-init $name $username $password

    let disk = $"(path-libvirt)/images/($name).qcow2"
    qemu-img convert -p -f $extension -O qcow2 $image $disk
    qemu-img resize $disk 64G

    (
        virt-install
        --arch $nu.os-info.arch
        --cloud-init $"user-data=($user_data)"
        --disk $"($disk),bus=virtio"
        --memory 8192
        --name $name
        --osinfo $osinfo
        --vcpus 4
        ...$params
        ...$args
    )
}

# Create a Windows virtual machine from an ISO disk.
def install-windows [domain: string cdrom: path drivers: string] {
    let libvirt = path-libvirt
    let params = match $nu.os-info.name {
        "linux" => [--cpu host-passthrough --graphics spice --virt-type kvm]
        "macos" => [--graphics vnc]
        _ => [--cpu host-passthrough --graphics vnc]
    }

    let disk = $"(path-libvirt)/cdroms/($domain).iso"
    let devices = $"(path-libvirt)/cdroms/($drivers | path basename).iso"
    cp $cdrom $disk
    cp $drivers $devices

    # Disk settings are chosen for speed based on recommendations at
    # https://unix.stackexchange.com/a/48584.
    (
        virt-install
        --arch x86_64
        --cdrom $disk
        --disk bus=virtio,cache=none,format=raw,io=native,size=128
        --disk $"bus=sata,device=cdrom,path=($devices)"
        --memory 8192
        --name $domain
        --osinfo win11
        --tpm model=tpm-tis,backend.type=emulator,backend.version=2.0
        --vcpus 4
        ...$params
    )
}

# Convenience script for QEMU and Virsh.
def --wrapped main [
    --log-level (-l): string = "debug" # Log level
    --version (-v) # Print version information
    ...args: string # Virsh arguments
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    if $version {
        print "Vimu 0.1.0"
    } else if $args == ["-h"] or $args == ["--help"] {
        (
            print
"Convenience script for QEMU and Virsh.

Usage: vimu [OPTIONS] <SUBCOMMAND>

Options:
  -h, --help        Print help information
  -v, --version     Print version information

Subcommands:
  bootstrap         Bootstrap virtual machine with Bootware
  create            Create virutal machine from default options
  detach-cdroms     Remove all cdrom disks from virtual machine
  gui               Connect to virtual machine as desktop
  install           Create a virtual machine from a cdrom or disk file
  port              Get host port mapping to domain
  remove            Delete virtual machine and its disk images
  setup             Configure machine for emulation
  snapshot-table    List snapshots for all virtual machines
  scp               Copy files between host and virtual machine
  ssh               Connect to virtual machine with SSH
  upload            Upload Vimu to guest machine"
        )
        if (which virsh | is-not-empty) {
            print "\nVirsh Options:\n"
            virsh ...$args
        }
    } else {
        virsh ...$args
    }
}

# Connect to virtual machine with Android debug bridge.
def --wrapped "main adb" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
    ...args: string # Android debug bridge arguments.
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    if not (virsh list --name | str contains $domain) {
        virsh start $domain
    }
    let port = main port $domain 5555
    adb -P $port connect ...$args
}

# Bootstrap virtual machine with Bootware.
def --wrapped "main bootstrap" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
    ...args: string # Bootware arguments.
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    if not (virsh list --name | str contains $domain) {
        virsh start $domain
    }
    let key = $"(path-config)/key"
    let port = main port $domain 22
    
    (
        bootware bootstrap --port $port --inventory localhost --temp-key $key
        ...$args
    )
}

# Create virutal machine from default options.
def "main create" [
    --iso (-i) # Use ISO version of domain
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    let arch = match $nu.os-info.arch {
        "aarch64" => "arm64"
        "x86_64" => "amd64"
    }
    let config = path-config
    setup-host

    # To find all osinfo options, run "virt-install --osinfo list".
    match $domain {
        "alpine" => {
            let image = $"($config)/image/alpine_amd64.qcow2"
            if not ($image | path exists) {
                log info "Downloading Alpine image."
                http get $"https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/generic_alpine-3.22.1-x86_64-bios-cloudinit-r0.qcow2"
                | save --progress $image
            }

            (
                main install --arch x86_64 --domain alpine
                --log-level $log_level --osinfo alpinelinux3.21 $image
            )
        }
        "android" => {
            let image = $"($config)/image/android_($arch).qcow2"
            if not ($image | path exists) {
                log info "Downloading Android image."
                http get $"https://gigenet.dl.sourceforge.net/project/android-x86/Release%209.0/android-x86_64-9.0-r2.iso"
                | save --progress $image
            }

            print "Follow instructions at https://youtu.be/MG7-S_88nDg?t=120 during first boot."
            (
                main install --arch x86_64 --domain android
                --log-level $log_level --osinfo android-x86-9.0 $image
            )
        }
        "arch" => {
            let image = $"($config)/image/arch_amd64.qcow2"
            if not ($image | path exists) {
                log info "Downloading Arch image."
                http get "https://gitlab.archlinux.org/archlinux/arch-boxes/-/package_files/9911/download"
                | save --progress $image
            }

            (
                main install --arch x86_64 --domain arch --log-level $log_level
                --osinfo archlinux $image
            )
        }
        "debian" => {
            let image = $"($config)/image/debian_($arch).qcow2"
            if not ($image | path exists) {
                log info "Downloading Debian image."
                http get $"https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-($arch)-daily.qcow2"
                | save --progress $image
            }

            (
                main install --domain debian --log-level $log_level
                --osinfo debian12 $image
            )
        }
        "freebsd" => {
            let image = $"($config)/image/freebsd_amd64.qcow2"
            if not ($image | path exists) {
                log info "Downloading FreeBSD image."
                http get "https://object-storage.public.mtl1.vexxhost.net/swift/v1/1dbafeefbd4f4c80864414a441e72dd2/bsd-cloud-image.org/images/freebsd/14.2/2024-12-08/zfs/freebsd-14.2-zfs-2024-12-08.qcow2"
                | save --progress $image
            }

            (
                main install --arch x86_64 --domain freebsd
                --log-level $log_level --osinfo freebsd14.2 $image
            )
        }
        "windows" => {
            let cdrom = $"($config)/cdrom/window_amd64.iso"
            let drivers = $"($config)/cdrom/winvirt_drivers.iso"

            if not ($cdrom | path exists) {
                print --stderr $"Windows ISO not found at ($cdrom)."
                print --stderr $"Download the ISO manually and try again."
                exit 1
            }
            if not ($drivers | path exists) {
                log info "Downloading Windows drivers."
                http get "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
                | save --progress $drivers
            }

            create-app "windows"
            install-windows windows $cdrom $drivers
        }
        _ => { error make { msg: $"Domain '($domain)' is not supported." } }
    }
}

# Remove all cdrom disks from virtual machine.
def "main detach-cdroms" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    let cdroms = virsh domblklist --details windows | from ssv | reject 0
    | where Device == "cdrom" | get Source

    for cdrom in $cdroms {
        log info $"Removing disk ($cdrom)."
        virsh detach-disk --persistent $domain $cdrom
    }
}

# Connect to virtual machine as desktop.
def "main gui" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
    ...args: string # Virt Viewer arguments
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    if not (virsh list --name | str contains $domain) {
        virsh start $domain
    }

    virt-viewer $domain ...$args
}

# Create a virtual machine from a cdrom or disk file.
def "main install" [
    --arch (-a): string # Virtual machine architecture
    --domain (-d): string # Virtual machine name
    --log-level (-l): string = "debug" # Log level
    --osinfo (-o): string = "generic" # Virt-install osinfo
    uri: string # Machine image URL or file path
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    setup-host
    let arch = $arch | default $nu.os-info.arch
    let config = path-config

    # Check if domain is already used by libvirt.
    if (virsh list --all --name | str contains $domain) {
        print --stderr "error: Domain is already in use"
        exit 1
    }

    let path = if ($uri | str starts-with "https://") {
        let image = $"($config)/image/($uri | path basename)"
        log info $"Downloading image from ($uri)."
        http get $uri | save --progress $image
        $image
    } else {
        $uri
    }

    let parts = $path | path parse
    let extension = $parts | get extension
    match $extension {
        "iso" => {
            create-app $domain
            install-cdrom $domain $osinfo $path
        }
        "img" | "qcow2" | "raw" | "vmdk" => {
            create-app $domain
            install-disk $domain $osinfo $path $extension
        }
        _ => {
            error make { msg: $"Unsupported extension '$extension'." }
        }
    }
}

# Get host port mapping to domain.
def "main port" [
    domain: string # Virtual machine name
    to: int # Destination port
] {
    # QEMU monitor commands are taken from
    # https://qemu-project.gitlab.io/qemu/system/monitor.html.
    let maps = virsh qemu-monitor-command --domain $domain --hmp "info usernet"
    | str trim | lines | skip 2 | str join "\n"
    | from ssv --minimum-spaces 1 --noheaders
    | where column0 == "TCP[HOST_FORWARD]" | select column3 column5
    | rename from to | into int from to

    let match = $maps | where to == $to | get --optional 0
    if $match == null {
        let port = port
        (
            virsh qemu-monitor-command --domain $domain --hmp
            $"hostfwd_add tcp::($port)-:($to)"
        )
        $port
    } else {
        $match.from
    }
}

# Delete virtual machine and its disk images.
def "main remove" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    let home = path-home
    let libvirt = path-libvirt
    let title = $domain | str capitalize

    # Stop domain if running.
    if (virsh list --name | str contains $domain) {
        virsh destroy $domain
    }

    # Delete domain snapshots and then domain itself.
    if (virsh list --all --name | str contains $domain) {
        for snapshot in (
            virsh snapshot-list --name --domain $domain | split words
        ) {
            virsh snapshot-delete --domain $domain $snapshot
        }
        virsh undefine --nvram --remove-all-storage $domain
    }

    match $nu.os-info.name {
        "linux" => {
            (
                rm --force --recursive
                $"($home)/.local/share/applications/($domain).desktop"
                $"($libvirt)/cdroms/($domain).iso"
            )
        }
        "macos" => {
            (
                rm --force --recursive
                $"($home)/Applications/($title).app"
                $"($libvirt)/cdroms/($domain).iso"
            )
        }
    }
}

# Configure machine for emulation.
def "main setup" [
    --log-level (-l): string = "debug" # Log level
    ...commands: string # Setup commands (desktop,guest,host) 
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase

    for command in $commands {
        match $command {
            "desktop" => { setup-desktop }
            "guest" => { setup-guest }
            "host" => { setup-host }
        }
    }
}

# List snapshots for all virtual machines.
def "main snapshot-table" [
    --log-level (-l): string = "debug" # Log level
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    virsh list --all --name | str trim | lines | each {|domain|
        virsh snapshot-list --parent $domain | str trim | lines | drop nth 1
        | str join "\n" | from ssv | insert Domain $domain | move Domain --first
    } | flatten
}

# Copy files between host and virtual machine.
def --wrapped "main scp" [
    --log-level (-l): string = "debug" # Log level
    ...args: string # Secure copy arguments
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase

    mut domain = ""
    mut params = $args
    for iter in ($args | enumerate) {
        let match = $iter.item | parse --regex '^(\w+@)?(?P<domain>\w+):.*$'
        if ($match | is-not-empty) {
            $domain = $match | get domain.0
            $params = $params | update $iter.index (
                $iter.item | str replace $"($domain):" "localhost:"
            )
        }
    }
    if ($domain | is-empty) {
        print --stderr $"No domain found in '($args | str join ' ')'."
        exit 1
    }
    
    if not (virsh list --name | str contains $domain) {
        virsh start $domain
    }
    let port = main port $domain 22
    tscp -i $"(path-config)/key" -P $port ...$params
}

# Connect to virtual machine with SSH.
def --wrapped "main ssh" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
    ...args: string
]: [nothing -> nothing string -> string] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    let key = $"(path-config)/key"
    if not (virsh list --name | str contains $domain) {
        virsh start $domain
    }
    let port = main port $domain 22

    # Appears that `$in` needs to be saved to a variable for mutliple uses.
    let pipe = $in
    if ($pipe | is-empty) {
        tssh -i $key -p $port localhost ...$args
    } else {
        $pipe | tssh -i $key -p $port localhost ...$args
    }
}

# Upload Vimu to guest machine.
def "main upload" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    const vimu = path self
    let info = os-info $domain

    # Copy Vimu to remote machine and install with super command.
    if $info.name == "windows" {
        main ssh $domain '
if (-not (Get-Command -ErrorAction SilentlyContinue nu)) {
    $NushellScript = Invoke-WebRequest -UseBasicParsing -Uri `
        https://scruffaluff.github.io/scripts/install/nushell.ps1
    Invoke-Expression "& { $NushellScript } --global"
}
New-Item -Force -ItemType Directory -Path "C:\Program Files\Bin" | Out-Null
if (-not (($Env:PathExt -Split ';.') -contains "NU") {
    Set-Content -Path "C:\Program Files\Bin\vimu.cmd" -Value @"
@echo off
nu "%~dnp0.nu" %*
"@
}
'
        main scp $vimu $"($domain):C:/Program Files/Bin/vimu.nu"
    } else {
        let check = main ssh $domain command -v nu | complete
        if $check.exit_code != 0 {
            http get https://scruffaluff.github.io/scripts/install/nushell.sh
            | main ssh $domain sh -s -- --global
        }

        main scp $vimu $"($domain):/tmp/vimu"
        main ssh $domain "
if [ -x \"$(command -v doas)\" ]; then
    doas install /tmp/vimu /usr/local/bin/vimu
else
    sudo install /tmp/vimu /usr/local/bin/vimu
fi
"
    }
}

# Get operating system information about a domain.
def os-info [domain: string] {
    let unix = (main ssh $domain "echo $PSVersionTable") | str trim | is-empty
    if $unix {
        let query = (main ssh $domain uname -ms) | str trim | str downcase
        | split row " "
        { arch: ($query | get 1) name: ($query | get 0) }
    } else {
        { arch: "x86_64" name: "windows" }
    }
}

# Get Vimu configuration folder.
def path-config [] {
    let home = path-home
    match $nu.os-info.name {
        "macos" => $"($home)/Library/Application Support/vimu"
        "windows" => $"($home)/AppData/Roaming/vimu"
        _ => $"($home)/.config/vimu"
    }
}

# Get user home folder.
def path-home [] {
    if $nu.os-info.name == "windows" {
        $env.HOME? | default $"($env.HOMEDRIVE?)($env.HOMEPATH?)"
    } else {
        $env.HOME? 
    }
}

# Get Libvirt folder.
def path-libvirt [] {
    $"(path-home)/.local/share/libvirt"
}

# Configure desktop environment on guest filesystem.
def setup-desktop [] {
    let super = find-super

    match $nu.os-info.name {
        "freebsd" => {
            # Configure GNOME desktop for FreeBSD.
            #
            # Based on instructions at
            # https://docs.freebsd.org/en/books/handbook/desktop/#gnome-environment.
            ^$super pkg update
            ^$super pkg install --yes gnome
            (
                ^$super nu --commands
                "'proc /proc procfs rw 0 0' | save --append /etc/fstab"
            )
            ^$super sysrc dbus_enable="YES"
            ^$super sysrc gdm_enable="YES"
            ^$super sysrc gnome_enable="YES"
        }
        "linux" => {
            if (which apk | is-not-empty) {
                ^$super apk update
                ^$super setup-desktop gnome
            } else if (which apt | is-not-empty) {
                # Avoid APT interactive configuration requests.
                $env.DEBIAN_FRONTEND = "noninteractive"
                ^$super -E apt-get update
                ^$super -E apt-get install --yes task-gnome-desktop
            } else if (which pacman | is-not-empty) {
                ^$super pacman --noconfirm --refresh --sync --sysupgrade
                ^$super pacman --noconfirm --sync gnome
                ^$super systemctl enable --now gdm.service
            }
        }
    }
}

# Configure guest filesystem.
def setup-guest [] {
    let home = path-home
    let super = find-super

    match $nu.os-info.name {
        "freebsd" => {
            ^$super pkg update
            # Seems as though openssh-server is builtin to FreeBSD.
            (
                ^$super pkg install --yes curl ncurses qemu-guest-agent rclone
                rsync topgrade
            )
            try { ^$super service qemu-guest-agent start }
            ^$super sysrc qemu_guest_agent_enable="YES"

            # Enable serial console on next boot.
            let content = '
boot_multicons="YES"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole,vidconsole"
'
            | str trim --left
            ^$super nu --commands $"'($content)' | save --force /boot/loader.conf"

            mkdir $"($home)/.config/rclone" $"($home)/.config/rstash"
        }
        "linux" => { setup-guest-linux $super }
        "windows" => { setup-guest-windows }
    }

    if (which bootware | is-empty) {
        http get https://scruffaluff.github.io/bootware/install.nu
        | nu -c $"($in | decode); main --global"
    }

    let programs = ["clear-cache" "fdi" "rgi" "rstash"]
    | where {|program| which $program | is-empty }
    if ($programs | is-not-empty) {
        http get https://scruffaluff.github.io/scripts/install/scripts.nu
        | nu -c $"($in | decode); main --global ($programs | str join ' ')"
    }

    if $nu.os-info == "windows" and not (
        "C:/Program Files/Tailscale" | path exists
    ) {
        let temp = mktemp --tmpdir --suffix ".msi"
        http get https://pkgs.tailscale.com/stable/tailscale-setup-1.86.2-amd64.msi
        | save --force --progress $temp
        msiexec /quiet /i $temp
    } else if (which tailscale | is-empty) {
        http get https://tailscale.com/install.sh | sh
    }

    let config = '
# Topgrade configuration file for updating system packages.
#
# For more infomation, visit
# https://github.com/topgrade-rs/topgrade/blob/main/config.example.toml.

[misc]
assume_yes = true
disable = ["certbot", "containers", "gem", "git_repos", "helm", "ruby_gems", "uv"]
no_retry = true
notify_each_step = false
skip_notify = true
'
    | str trim --left | save --force $"($home)/.config/topgrade.toml"
}

# Configure guest filesystem for Linux.
def setup-guest-linux [super: string] {
    let home = path-home

    if (which apk | is-not-empty) {
        ^$super apk update
        (
            ^$super apk add curl ncurses openssh-server python3 qemu-guest-agent
            rclone spice-vdagent
        )
        ^$super rc-update add qemu-guest-agent
        ^$super service qemu-guest-agent start
        # Starting spice-vdagentd service causes an error.
        ^$super rc-update add spice-vdagentd
        ^$super rc-update add sshd
        ^$super service sshd start
    } else if (which apt-get | is-not-empty) {
        # Avoid APT interactive configuration requests.
        $env.DEBIAN_FRONTEND = "noninteractive"
        ^$super -E apt-get update
        (
            ^$super -E apt-get install --yes curl libncurses6 openssh-server
            qemu-guest-agent rclone spice-vdagent
        )
    } else if (which dnf | is-not-empty) {
        ^$super dnf makecache
        (
            ^$super dnf install --assumeyes curl ncurses openssh-server
            qemu-guest-agent rclone spice-vdagent
        )
    } else if (which pacman | is-not-empty) {
        ^$super pacman --noconfirm --refresh --sync --sysupgrade
        (
            ^$super pacman --noconfirm --sync curl ncurses openssh
            qemu-guest-agent rclone spice-vdagent
        )
    } else if (which zypper | is-not-empty) {
        ^$super zypper update --no-confirm
        (
            ^$super zypper install --no-confirm curl ncurses openssh-server
            qemu-guest-agent rclone spice-vdagent
        )
    }

    # Services qemu-guest-agnet and spice-vdagentd appear to only available as
    # on demand services.
    if (which systemctl | is-not-empty) {
        let services = systemctl list-units --type=service --all
        for service in ["serial-getty@ttyS0" "ssh" "sshd"] {
            if ($services | str contains $"($service).service") {
                log debug $"Enabling ($service) service."
                ^$super systemctl enable --now $"($service).service"
            }
        }
    }

    if (which topgrade | is-empty) {
        let tmp_dir = mktemp --directory --tmpdir
        let version = http get https://formulae.brew.sh/api/formula/topgrade.json
        | get versions.stable
        let file_name = (
            $"topgrade-v($version)-($nu.os-info.arch)-unknown-linux-musl.tar.gz"
        )

        http get $"https://github.com/topgrade-rs/topgrade/releases/download/v($version)/($file_name)"
        | save --progress $"($tmp_dir)/topgrade.tar.gz"
        tar xf $"($tmp_dir)/topgrade.tar.gz" -C $tmp_dir
        ^$super install $"($tmp_dir)/topgrade" /usr/local/bin/topgrade
    }

    mkdir $"($home)/.config/rclone" $"($home)/.config/rstash"
}

# Configure guest filesystem for Windows.
def setup-guest-windows [] {
    let home = path-home

    if (which rclone | is-empty) {
        let tmp_dir = mktemp --directory --tmpdir | str replace --all '\' '/'
        let rclone_uri = http get https://raw.githubusercontent.com/ScoopInstaller/Main/refs/heads/master/bucket/rclone.json
        | get architecture.64bit.url
        http get $rclone_uri | save --progress $"($tmp_dir)/rclone.zip"
        powershell -command $"
$ProgressPreference = 'SilentlyContinue'
Expand-Archive -DestinationPath '($tmp_dir)' -Path '($tmp_dir)/rclone.zip'
"
        let rclone = glob $"($tmp_dir)/**/rclone.exe" | first
        cp $rclone "C:/Program Files/Bin/rclone.exe"
    }

    mkdir $"($home)/.config/rclone" $"($home)/AppData/Roaming/rstash"
}

# Configure host machine.
def setup-host [] {
    let config = path-config
    let home = path-home
    let libvirt = path-libvirt
    mkdir $config $"($libvirt)/cdroms" $"($libvirt)/images"

    if not ($"($config)/icon.icns" | path exists) {
        http get https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/main/data/image/icon.icns
        | save $"($config)/icon.icns"
    }
    if not ($"($config)/icon.ico" | path exists) {
        http get https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/main/data/image/icon.ico
        | save $"($config)/icon.ico"
    }
    if not ($"($config)/icon.png" | path exists) {
        http get https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/main/data/image/icon.png
        | save $"($config)/icon.png"
    }
    if not ($"($config)/icon.svg" | path exists) {
        http get https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/main/data/image/icon.svg
        | save $"($config)/icon.svg"
    }

    create-key
    let programs = ["tscp" "tssh"]
    | where {|program| which $program | is-empty }
    if ($programs | is-not-empty) {
        http get https://scruffaluff.github.io/scripts/install/scripts.nu
        | nu -c $"($in | decode); main --global ($programs | str join ' ')"
    }
}
