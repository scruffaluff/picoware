#!/usr/bin/env nu
#
# Convenience commands for Virsh and QEMU.

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

# Connect to virtual machine.
def connect [
    start: bool # Start virtual machine if not running
    type: string # Connection type (ssh, view)
    domain: string # Virtual machine name
] {
    if $start and not (virsh list --name | str contains $domain) {
        virsh start $domain
    }

    match $type {
        "ssh" => {
            let home = get-home
            let port = port
            (
                virsh qemu-monitor-command --domain $domain
                --hmp $"hostfwd_add tcp::($port)-:22"
            )
            tssh -i $"($home)/.vimu/key" -p $port localhost
            
        }
        "view" => { virt-viewer $domain }
        _ => { 
            print --stderr $"Invalid connection type '($type)'."
            exit 2
        }
    }
}

# Create application bundle or desktop entry.
def create-app [domain: string] {
    let home = get-home

    match $nu.os-info.name {
        "linux" => {
            $"
[Desktop Entry]
Exec=vimu start desktop ($domain)
Icon=($home)/.vimu/waveform.svg
Name=($domain | str capitalize)
Terminal=false
Type=Application
Version=1.0
"
        | save --force $"($home)/.local/share/applications/vimu_($domain).desktop"
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
    )
}

# Create a virtual machine from a qcow2 disk.
def install-disk [name: string osinfo: string path: string extension: string] {
    let home = get-home
    let params = match $nu.os-info.name {
        "linux" => [--cpu host-model --graphics spice --virt-type kvm]
        "macos" => [--graphics vnc]
        _ => [--cpu host-model --graphics vnc]
    }

    print "Create user account for virtual machine."
    let username = input "Username: "
    let password = ask-password
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
    )
}

# Convenience commands for Virsh and QEMU.
def --wrapped main [
    --version (-v) # Print version information
    ...$args: string # Virsh arguments
] {
    if $version {
        print "Vimu 0.0.2"
    } else if ("-h" in $args) or ("--help" in $args) {
        (
            print
"Convenience commands for Virsh and QEMU.

Usage: vimu [OPTIONS] <SUBCOMMAND>

Options:
  -h, --help        Print help information
  -v, --version     Print version information

Subcommands:
  create      Create virutal machine from default options
  install     Create a virtual machine from a cdrom or disk file
  remove      Delete virtual machine and its disk images
  setup       Configure machine for emulation
  ssh         Connect to virtual machine with SSH
  view        Connect to virtual machine as desktop

Virsh Options:"
        )
        virsh --help
    } else {
        virsh ...$args
    }
}

# Create virutal machine from default options.
def "main create" [
    --gui (-g) # Use GUI version of domain
    --log-level (-l): string = "debug" # Log level
    domain: string@domain-choices # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    let arch = match $nu.os-info.arch {
        "aarch64" => "arm64"
        "x86_64" => "amd64"
    }
    let home = get-home
    main setup host

    match $domain {
        "alpine" => {
            let image = $"($home)/.vimu/alpine_($arch).qcow2"
            if not ($image | path exists) {
                log info "Downloading Alpine image."
                http get $"https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/nocloud_alpine-3.22.1-($nu.os-info.arch)-uefi-cloudinit-r0.qcow2"
                | save --progress $image
            }
            (
                main install --domain alpine --log-level $log_level
                --osinfo alpinelinux3.21 $image
            )
        }
        "debian" => {
            let image = $"($home)/.vimu/debian_($arch).qcow2"
            if not ($image | path exists) {
                log info "Downloading Debian image."
                http get $"https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-($arch).qcow2"
                | save --progress $image
            }
            (
                main install --domain debian --log-level $log_level
                --osinfo debian12 $image
            )
        }
        _ => { error make { msg: $"Domain '($domain)' is not supported." } }
    }
}

# Create a virtual machine from a cdrom or disk file.
def "main install" [
    --domain (-d): string # Virtual machine name
    --log-level (-l): string = "debug" # Log level
    --osinfo (-o): string = "generic" # Virt-install osinfo
    uri: string # Machine image URL or file path
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    main setup host
    let home = get-home

    # Check if domain is already used by libvirt.
    if (virsh list --all --name | str contains $domain) {
        print --stderr "error: Domain is already in use"
        exit 1
    }

    let path = if ($uri | str starts-with "https://") {
        let image = $"($home)/.vimu/($uri | path basename)"
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
    --log-level (-l): string = "debug" # Log level
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
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
        $"($home)/.local/share/applications/vimu_($domain).desktop"
        $"($home)/.local/share/libvirt/cdroms/($domain).iso"
    )
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
        $"($home)/.vimu"
        $"($home)/.local/share/libvirt/cdroms"
        $"($home)/.local/share/libvirt/images"
    )

    http get https://raw.githubusercontent.com/phosphor-icons/core/main/assets/regular/waveform.svg
    | save --force $"($home)/.vimu/waveform.svg"

    if not ($"($home)/.vimu/key" | path exists) {
        ssh-keygen -N '' -q -f $"($home)/.vimu/key" -t ed25519 -C vimu
        if $nu.os-info.name != "windows" {
            chmod 600 $"($home)/.vimu/key" $"($home)/.vimu/key.pub"
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
}

# Upload Vimu to guest machine.
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
        | tssh -i $"($home)/.vimu/key" -p 2022 localhost sh -s -- --global
    )
    # Copy Vimu to remote machine and install with super command.
    tscp -i $"($home)/.vimu/key" -P 2022 $script localhost:/tmp/vimu
    (
        tssh -i $"($home)/.vimu/key" -p 2022 localhost sudo install
        /tmp/vimu /usr/local/bin/vimu
    )
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

# Connect to virtual machine as desktop.
def "main view" [
    --log-level (-l): string = "debug" # Log level
    --start (-s) # Start virtual machine if not running
    domain: string # Virtual machine name
] {
    $env.NU_LOG_LEVEL = $log_level | str upcase
    connect $start view $domain
}
