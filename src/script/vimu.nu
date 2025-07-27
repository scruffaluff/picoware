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
    let home = get-home
    let pub_key = open $"($home)/.vimu/key.pub"
    let content = $"
#cloud-config

hostname: "($domain)"
preserve_hostname: false
users:
  - doas: [permit nopass ($username)]
    lock_passwd: false
    name: "($username)"
    plain_text_passwd: "($password)"
    ssh_authorized_keys:
      - "($pub_key)"
    sudo: ALL=\(ALL\) NOPASSWD:ALL
"

    let path = mktemp --tmpdir --suffix .yaml
    $content | save --force $path
    $path
}

# Connect to virtual machine.
def connect [
    start: bool # Start virtual machine if not running
    type: string # Connection type (console, gui, ssh)
    domain: string # Virtual machine name
] {
    if $start and not (virsh list --name | str contains $domain) {
        virsh start $domain
    }

    match $type {
        "adb" => {
            let port = port
            (
                virsh qemu-monitor-command --domain $domain
                --hmp $"hostfwd_add tcp::($port)-:5555"
            )
            adb -P $port connect
        }
        "console" => { virsh console $domain }
        "gui" => { virt-viewer $domain }
        "ssh" => {
            let home = get-home
            let port = port
            (
                virsh qemu-monitor-command --domain $domain
                --hmp $"hostfwd_add tcp::($port)-:22"
            )
            tssh -i $"($home)/.vimu/key" -p $port localhost
        }
        _ => { 
            print --stderr $"Invalid connection type '($type)'."
            exit 2
        }
    }
}

# Create application desktop entry.
def create-app [domain: string] {
    let home = get-home
    let title = $domain | str capitalize

    match $nu.os-info.name {
        "linux" => {
            let dest = $"($home)/.local/share/applications"
            mkdir $dest
            (
                $"
[Desktop Entry]
Exec=vimu gui ($domain)
Icon=($home)/.vimu/icon.svg
Name=($title)
Terminal=false
Type=Application
Version=1.0
"
                | str trim --left
                | save --force $"($dest)/vimu_($domain).desktop"
            )
        }
        "macos" => {
            let dest = $"($home)/Applications/($title).app/Contents"
            mkdir $"($dest)/MacOS" $"($dest)/Resources"
            cp $"($home)/.vimu/icon.png" $"($dest)/Resources/icon.png"
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
  <string>icon</string>
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
                | save $"($dest)/Info.plist"
            )
        }
    }
}

# Create application entrypoint.
def create-entry [domain: string path: string] {
    const folder = path self | path dirname
    $"
#!/usr/bin/env sh
set -eu

export PATH="($folder):${PATH}"
exec vimu gui ($domain)
"  | str trim --left | save --force $path
    chmod +x $path
}

# Find command to elevate as super user.
def find-super [] {
    if (is-admin) {
        ""
    } else if $nu.os-info.name == "windows" {
        error make { msg: "
System level installation requires an administrator console.
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

# Parse user home directory from environment variables.
def get-home [] {
    if $nu.os-info.name == "windows" {
        $"($env.HOMEDRIVE)($env.HOMEPATH)"
    } else {
        $env.HOME
    }
}

# Create a virtual machine from an ISO disk.
def --wrapped install-cdrom [
    domain: string osinfo: string path: string ...args: string
] {
    let home = get-home
    let params = match $nu.os-info.name {
        "linux" => [--cpu host-model --graphics spice --virt-type kvm]
        "macos" => [--graphics vnc]
        _ => [--cpu host-model --graphics vnc]
    }
    let cdrom = $"($home)/.local/share/libvirt/cdroms/($domain).iso"
    cp $path $cdrom

    (
        virt-install
        --arch $nu.os-info.arch
        --cdrom $cdrom
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
    name: string osinfo: string path: string extension: string ...args: string
] {
    let home = get-home
    let params = match $nu.os-info.name {
        "linux" => [--cpu host-model --graphics spice --virt-type kvm]
        "macos" => [--graphics vnc]
        _ => [--cpu host-model --graphics vnc]
    }

    print "Create user account for virtual machine."
    let username = $env.VIMU_USERNAME? | default { input "Username: " }
    let password = $env.VIMU_PASSWORD? | default { ask-password }
    let user_data = cloud-init $name $username $password

    let folder = $"($home)/.local/share/libvirt/images"
    let destpath = $"($folder)/($name).qcow2"
    mkdir $folder

    qemu-img convert -p -f $extension -O qcow2 $path $destpath
    qemu-img resize $destpath 64G
    (
        virt-install
        --arch $nu.os-info.arch
        --cloud-init $"user-data=($user_data)"
        --disk $"($destpath),bus=virtio"
        --memory 8192
        --name $name
        --osinfo $osinfo
        --vcpus 4
        ...$params
        ...$args
    )
}

# Create a Windows virtual machine from an ISO disk.
def install-windows [domain: string cdrom: string drivers: string] {
    let home = get-home
    let params = match $nu.os-info.name {
        "linux" => [--cpu host-model --graphics spice --virt-type kvm]
        "macos" => [--graphics vnc]
        _ => [--cpu host-model --graphics vnc]
    }

    (
        virt-install
        --arch x86_64
        --cdrom $cdrom
        --disk bus=virtio,format=qcow2,size=64
        --disk $"bus=sata,device=cdrom,path=($drivers)"
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
    --version (-v) # Print version information
    ...args: string # Virsh arguments
] {
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
  create      Create virutal machine from default options
  gui         Connect to virtual machine as desktop
  install     Create a virtual machine from a cdrom or disk file
  remove      Delete virtual machine and its disk images
  setup       Configure machine for emulation
  ssh         Connect to virtual machine with SSH
  upload      Upload Vimu to guest machine

Virsh Options:"
        )
        if (which virsh | is-not-empty) {
            virsh ...$args
        }
    } else {
        virsh ...$args
    }
}

# Connect to virtual machine with Android debug bridge.
def "main adb" [
    --log-level (-l): string = "debug" # Log level
    --start (-s) # Start virtual machine if not running
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    connect $start adb $domain
}

# Create virutal machine from default options.
def "main create" [
    --gui (-g) # Use GUI version of domain
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    let arch = match $nu.os-info.arch {
        "aarch64" => "arm64"
        "x86_64" => "amd64"
    }
    let home = get-home
    main setup host

    # To find all osinfo options, run "virt-install --osinfo list".
    match $domain {
        "alpine" => {
            let image = $"($home)/.vimu/alpine_amd64.qcow2"
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
            let image = $"($home)/.vimu/android_($arch).qcow2"
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
            let image = $"($home)/.vimu/arch_amd64.qcow2"
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
            let image = $"($home)/.vimu/debian_($arch).qcow2"
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
            let image = $"($home)/.vimu/freebsd_amd64.qcow2"
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
            let cdrom = $"($home)/.vimu/window_amd64.iso"
            let drivers = $"($home)/.vimu/winvirt_drivers.iso"

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

# Connect to virtual machine as desktop.
def "main gui" [
    --log-level (-l): string = "debug" # Log level
    --start (-s) # Start virtual machine if not running
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    connect $start gui $domain
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
    main setup host
    let arch = $arch | default $nu.os-info.arch
    let home = get-home

    # Check if domain is already used by libvirt.
    if (virsh list --all --name | str contains $domain) {
        print --stderr "error: Domain is already in use"
        exit 1
    }

    let path = if ($uri | str starts-with "https://") {
        let image = $"($home)/.vimu/($uri | path basename)"
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

# Delete virtual machine and its disk images.
def "main remove" [
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    let home = get-home
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
                $"($home)/.local/share/applications/($title).desktop"
                $"($home)/.local/share/libvirt/cdroms/($domain).iso"
            )
        }
        "macos" => {
            (
                rm --force --recursive
                $"($home)/Applications/($title).app"
                $"($home)/.local/share/libvirt/cdroms/($domain).iso"
            )
        }
    }
}

# Configure machine for emulation.
def "main setup" [
    --log-level (-l): string = "debug" # Log level
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
}

# Configure desktop environment on guest filesystem.
def "main setup desktop" [] {
    let super = find-super

    if (which apk | is-not-empty) {
        ^$super apk update
        ^$super setup-desktop gnome
    } else if (which apt | is-not-empty) {
        ^$super apt-get update
        ^$super apt-get install --yes task-gnome-desktop
    } else if (which pacman | is-not-empty) {
        ^$super pacman --noconfirm --refresh --sync --sysupgrade
        ^$super pacman --noconfirm --sync gnome
        ^$super systemctl enable --now gdm.service
    } else if (which pkg | is-not-empty) {
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
}

# Configure guest filesystem.
def "main setup guest" [] {
    let home = get-home
    let super = find-super

    if (which apk | is-not-empty) {
        ^$super apk update
        ^$super apk add curl ncurses openssh-server python3 qemu-guest-agent spice-vdagent
        ^$super rc-update add qemu-guest-agent
        ^$super service qemu-guest-agent start
        # Starting spice-vdagentd service causes an error.
        ^$super rc-update add spice-vdagentd
        ^$super rc-update add sshd
        ^$super service sshd start
    } else if (which apt-get | is-not-empty) {
        ^$super apt-get update
        with-env { DEBIAN_FRONTEND: noninteractive } {
            (
                ^$super apt-get install --yes curl libncurses6 openssh-server
                qemu-guest-agent spice-vdagent
            )
        }
    } else if (which dnf | is-not-empty) {
        ^$super dnf check-update
        (
            ^$super dnf install --assumeyes curl ncurses openssh-server
            qemu-guest-agent spice-vdagent
        )
    } else if (which pacman | is-not-empty) {
        ^$super pacman --noconfirm --refresh --sync --sysupgrade
        (
            ^$super pacman --noconfirm --sync curl ncurses openssh
            qemu-guest-agent spice-vdagent
        )
    } else if (which pkg | is-not-empty) {
        ^$super pkg update
        # Seems as though openssh-server is builtin to FreeBSD.
        ^$super pkg install --yes curl ncurses qemu-guest-agent rsync topgrade
        try { ^$super service qemu-guest-agent start }
        ^$super sysrc qemu_guest_agent_enable="YES"
        # Enable serial console on next boot.
        let content = '
boot_multicons="YES"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole,vidconsole"
'
        ^$super nu --commands $"'($content)' | save --force /boot/loader.conf"
    } else if (which zypper | is-not-empty) {
        ^$super zypper update --no-confirm
        ^$super zypper install --no-confirm curl ncurses openssh-server qemu-guest-agent spice-vdagent
    }

    if (which systemctl | is-not-empty) {
        let services = systemctl list-units --type=service --all
        for service in [
            "qemu-guest-agent" "serial-getty@ttyS0" "spice-vdagentd" "ssh"
            "sshd"
        ] {
            if ($services | str contains $"($service).service") {
                try { ^$super systemctl enable --now $"($service).service" }
            }
        }
    }

    http get https://scruffaluff.github.io/scripts/install/scripts.nu
    | nu -c $"($in | decode); main --global clear-cache fdi rgi rstash"

    if $nu.os-info.name == "linux" and (which topgrade | is-empty) {
        let tmp_dir = mktemp --directory --tmpdir
        let version = (
            http get https://formulae.brew.sh/api/formula/topgrade.json
            | get versions.stable
        )
        let file_name = (
            $"topgrade-v($version)-($nu.os-info.arch)-unknown-linux-musl.tar.gz"
        )

        (
            http get
            $"https://github.com/topgrade-rs/topgrade/releases/download/v($version)/($file_name)"
            | save --progress $"($tmp_dir)/topgrade.tar.gz"
        )
        tar xf $"($tmp_dir)/topgrade.tar.gz" -C $tmp_dir
        ^$super install $"($tmp_dir)/topgrade" /usr/local/bin/topgrade
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
    mkdir $"($home)/.config"
    $config | save --force $"($home)/.config/topgrade.toml"
}

# Configure host machine.
def "main setup host" [] {
    let home = get-home
    (
        mkdir
        $"($home)/.vimu"
        $"($home)/.local/share/libvirt/cdroms"
        $"($home)/.local/share/libvirt/images"
    )

    if not ($"($home)/.vimu/icon.png" | path exists) {
        http get https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/main/data/image/icon.png
        | save $"($home)/.vimu/icon.png"
    }
    if not ($"($home)/.vimu/icon.svg" | path exists) {
        http get https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/main/data/image/icon.svg
        | save $"($home)/.vimu/icon.svg"
    }

    if not ($"($home)/.vimu/key" | path exists) {
        ssh-keygen -N '' -q -f $"($home)/.vimu/key" -t ed25519 -C vimu
        if $nu.os-info.name != "windows" {
            chmod 600 $"($home)/.vimu/key" $"($home)/.vimu/key.pub"
        }
    }
}

# Connect to virtual machine with SSH.
def "main ssh" [
    --log-level (-l): string = "debug" # Log level
    --start (-s) # Start virtual machine if not running
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    connect $start ssh $domain
}

# Upload Vimu to guest machine.
def "main upload" [
    domain: string # Virtual machine name
] {
    const vimu = path self
    if ((virsh domstate $domain | str trim) != "running") {
        virsh start $domain
    }

    let key = $"(get-home)/.vimu/key"
    let port = port
    (
        virsh qemu-monitor-command --domain $domain
        --hmp $"hostfwd_add tcp::($port)-:22"
    )

    let check = tssh -i $key -p $port localhost command -v nu | complete
    if $check.exit_code != 0 {
        http get https://scruffaluff.github.io/scripts/install/nushell.sh
        | tssh -i $key -p $port localhost sh -s -- --global
    }

    # Copy Vimu to remote machine and install with super command.
    tscp -i $key -P $port $vimu localhost:/tmp/vimu
    tssh -i $key -p $port localhost "
if [ -x \"$(command -v doas)\" ]; then
    doas install /tmp/vimu /usr/local/bin/vimu
else
    sudo install /tmp/vimu /usr/local/bin/vimu
fi
"
}
