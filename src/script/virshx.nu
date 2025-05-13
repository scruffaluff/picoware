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

def domain-choices [] {
    ["alpine" "debian"]
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
    --version (-v) # Print version information
] {
    if ($version) {
        version
    }
}

# Create virutal machine from default options.
def "main create" [domain: string@domain-choices] {
    let home = get-home
    main setup host

    match $domain {
        "alpine" => {
            let image = $"($home)/.virshx/alpine_amd64.iso"
            if not ($image | path exists) {
                http get "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso"
                | save --progress $image
            }
            main install --domain alpine --osinfo alpinelinux3.21 $image
        }
        "debian" => {
            let image = $"($home)/.virshx/debian_amd64.qcow2"
            if not ($image | path exists) {
                http get "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
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
    path: string
] {
    main setup host

    # Check if domain is already used by libvirt.
    if (virsh list --all --name | str contains $domain) {
        print --stderr "error: Domain is already in use"
        exit 1
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

# Configure machine for emulation.
def "main setup" [] {}

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

def version [] {
    "Virshx 0.0.2"
}
