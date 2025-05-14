#!/usr/bin/env nu
#
# Extra convenience commands for Virsh and Libvirt.

# Generate cloud init data.
def cloud-init [domain: string username: string password: string] {
    let home = get-home
    let pub_key = open $"($home)/.virshx/key.pub"
    let content = $"
#cloud-config

hostname: "($domain)"
preserve_hostname: true
users:
  - lock_passwd: false
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

# Create application bundle or desktop entry.
def create-app [domain: string] {
    let home = get-home

    match $nu.os-info.name {
        "linux" => {
            $"
[Desktop Entry]
Exec=virshx start desktop ($domain)
Icon=($home)/.virshx/waveform.svg
Name=($domain | str capitalize)
Terminal=false
Type=Application
Version=1.0
"
        | save --force $"($home)/.local/share/applications/virshx_($domain).desktop"
        }
    }
}

# Default domain choices.
def domain-choices [] {
    ["alpine" "debian"]
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
def install-cdrom [domain: string osinfo: string path: string] {
    let home = get-home
    let params = match $nu.os-info.name {
        "linux" => [--virt-type kvm]
        _ => []
    }
    let cdrom = $"($home)/.local/share/libvirt/cdroms/($domain).iso"
    cp $path $cdrom

    (
        virt-install
        --arch $nu.os-info.arch
        --cdrom $cdrom
        --cpu host
        --disk bus=virtio,format=qcow2,size=64
        --graphics spice
        --memory 8192
        --name $domain
        --osinfo $osinfo
        --vcpus 4
        ...$params
    )
}

# Create a virtual machine from a qcow2 disk.
def install-disk [name: string osinfo: string path: string extension: string] {
    let home = get-home
    let params = match $nu.os-info.name {
        "linux" => [--virt-type kvm]
        _ => []
    }

    let username = input "username: "
    let password = input --suppress-output "password: "
    let user_data = cloud-init $name $username $password

    let folder = $"($home)/.local/share/libvirt/images"
    let destpath = $"($folder)/($name).qcow2"
    mkdir "${folder}"

    qemu-img convert -p -f $extension -O qcow2 $path $destpath
    qemu-img resize $destpath 64G
    (
        virt-install
        --arch $nu.os-info.arch
        --cloud-init $"user-data=($user_data)"
        --cpu host
        --disk $"($destpath),bus=virtio"
        --graphics spice
        --memory 8192
        --name $name
        --osinfo $osinfo
        --vcpus 4
        ...$params
    )
}


# Extra convenience commands for Virsh and Libvirt.
def main [
    --version (-v) # Print Virshx version string
] {
    if $version {
        print "Virshx 0.0.2"
        exit 0
    }
}

# Create virutal machine from default options.
def "main create" [
    --gui (-g) # Use GUI version of domain
    domain: string@domain-choices # Virtual machine name
] {
    let home = get-home
    main setup host

    match $domain {
        "alpine" => {
            let image = $"($home)/.virshx/alpine_amd64.qcow2"
            if not ($image | path exists) {
                http get "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/cloud/nocloud_alpine-3.21.2-x86_64-uefi-cloudinit-r0.qcow2"
                | save --progress $image
            }
            main install --domain alpine --osinfo alpinelinux3.21 $image
        }
        "debian" => {
            let image = $"($home)/.virshx/debian_amd64.qcow2"
            if not ($image | path exists) {
                http get "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
                | save --progress $image
            }
            main install --domain debian --osinfo debian12 $image
        }
        _ => { error make { msg: $"Domain '($domain)' is not supported." } }
    }
}

# Create a virtual machine from a cdrom or disk file.
def "main install" [
    --domain (-d): string # Virtual machine name
    --osinfo (-o): string = "generic" # Virt-install osinfo
    uri: string # Machine image URL or file path
] {
    main setup host
    let home = get-home

    # Check if domain is already used by libvirt.
    if (virsh list --all --name | str contains $domain) {
        print --stderr "error: Domain is already in use"
        exit 1
    }

    let path = if ($uri | str starts-with "https://") {
        let image = $"($home)/.virshx/($uri | path basename)"
        http get $uri | save --progress $image
        $image
    } else {
        $uri
    }

    let extension = $path | path parse | get extension
    match $extension {
        "iso" => { install-cdrom $domain $osinfo $path }
        "img" | "qcow2" | "raw" | "vmdk" => {
            install-disk $domain $osinfo $path $extension
        }
        _ => {
            error make { msg: $"Unsupported extension '$extension'." }
        }
    }

    create-app $domain
}

# Delete virtual machine and its disk images.
def "main remove" [
    domain: string # Virtual machine name
] {
    let home = get-home

    # Stop domain if running.
    if (virsh list --name | str contains $domain) {
        virsh destroy $domain
    }

    # Detele domain snapshots and then domain itself.
    if (virsh list --all --name | str contains $domain) {
        for snapshot in (
            virsh snapshot-list --name --domain $domain | split words
        ) {
            virsh snapshot-delete --domain $domain $snapshot
        }
        virsh undefine --nvram --remove-all-storage $domain
    }

    (
        rm --force 
        $"($home)/.local/share/applications/virshx_($domain).desktop"
        $"($home)/.local/share/libvirt/cdroms/($domain).iso"
    )
}

# Configure machine for emulation.
def "main setup" [] {}

# Configure desktop environment on guest filesystem.
def "main setup desktop" [] {
    let super = find-super

    if (which apk | is-not-empty) {
        ^$super apk update
        ^$super setup-desktop gnome
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
        ^$super pkg install --yes curl ncurses qemu-guest-agent rsync
        ^$super service qemu-guest-agent start
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
        # ^$super systemctl enable --now qemu-guest-agent.service
        ^$super systemctl enable --now serial-getty@ttyS0.service
        # ^$super systemctl enable --now spice-vdagentd.service
        ^$super systemctl enable --now ssh.service
    }

    if (which topgrade | is-empty) {
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
}

# Configure host machine.
def "main setup host" [] {
    let home = get-home
    (
        mkdir
        $"($home)/.virshx"
        $"($home)/.local/share/libvirt/cdroms"
        $"($home)/.local/share/libvirt/images"
    )

    http get https://raw.githubusercontent.com/phosphor-icons/core/main/assets/regular/waveform.svg
    | save --force $"($home)/.virshx/waveform.svg"

    if not ($"($home)/.virshx/key" | path exists) {
        ssh-keygen -N '' -q -f $"($home)/.virshx/key" -t ed25519 -C virshx
        if $nu.os-info.name != "windows" {
            chmod 600 $"($home)/.virshx/key" $"($home)/.virshx/key.pub"
        }
    }
}

# Forward host port to guest domain 22 port for SSH.
def "main setup port" [
    domain: string # Virtual machine name
] {
    # Setup SSH port.
    virsh qemu-monitor-command --domain $domain --hmp "hostfwd_add tcp::2022-:22"
    # Setup Android debug port.
    virsh qemu-monitor-command --domain $domain --hmp "hostfwd_add tcp::4444-:5555"

    print $"You can now SSH login to ($domain) with command 'ssh -i ~/.virshx/key -p 2022 localhost'."
}

# Upload Virshx to guest machine.
def "main setup upload" [
    domain: string # Virtual machine name
] {
    const script = path self
    let home = get-home
    if ((virsh domstate $domain | str trim) != "running") {
        virsh start $domain
    }

    # Install Nushell by piping Curl output remote shell.
    (
        curl --fail --location 
        --show-error https://scruffaluff.github.io/scripts/install/nushell.sh
        | tssh -i $"($home)/.virshx/key" -p 2022 localhost sh -s -- --global
    )
    # Copy Virshx to remote machine and install with super command.
    tscp -i $"($home)/.virshx/key" -P 2022 $script localhost:/tmp/virshx
    (
        tssh -i $"($home)/.virshx/key" -p 2022 localhost sudo install
        /tmp/virshx /usr/local/bin/virshx
    )
}

# Run virtual machine and connect to its console.
def "main start console" [
    domain: string # Virtual machine name
] {
  virsh start $domain
  main setup port $domain
  virsh console $domain
}

# Run virtual machine as a desktop application.
def "main start desktop" [
    domain: string # Virtual machine name
] {
  virsh start $domain
  main setup port $domain
  virt-viewer $domain
}

# Run virtual machine ine with QEMU commands.
def "main start qemu" [
    domain: string # Virtual machine name
] {
}

# Run Virsh command.
def --wrapped "main v" [...$args: string] {
    virsh ...$args
}
