#!/usr/bin/env nu
#
# Extra convenience commands for Virsh and Libvirt.

# Create application bundle or desktop entry.
def create_app [name: string] {
    let home = get_home

    match $nu.os-info.name {
        "linux" => {
            $"
[Desktop Entry]
Exec=virshx start desktop ($name)
Icon=($home)/.virshx/waveform.svg
Name=($name | str capitalize)
Terminal=false
Type=Application
Version=1.0
"
        | save --force $"($home)/.local/share/applications/virshx_($name).desktop"
        }
    }
}

# Parse user home directory from environment variables.
def get_home [] {
    if $nu.os-info.name == "windows" {
        $"($env.HOMEDRIVE)($env.HOMEPATH)"
    } else {
        $env.HOME
    }
}

# Create a virtual machine from an ISO disk.
def install_cdrom [name: string osinfo: string path: string] {
    let home = get_home
    let params = if $nu.os-info.name == "linux" { [--virt-type kvm] } else { [] }
    let cdrom = $"($home)/.local/share/libvirt/cdroms/($name).iso"
    cp $path $cdrom

    (
        virt-install
        --arch $nu.os-info.arch
        --cdrom $cdrom
        --cpu host
        --disk bus=virtio,format=qcow2,size=64
        --graphics spice
        --memory 8192
        --name $name
        --osinfo $osinfo
        --vcpus 4
        ...$params
    )
}

# Download disk for domain and install with defaults.
def install_default [domain: string] {
    let home = get_home

    match $domain {
        "alpine" => {
            let image = $"($home)/.virshx/alpine_amd64.iso"
            if not ($image | path exists) {
                http get "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso"
                | save --progress $image
            }
            main install --domain alpine --osinfo alpinelinux3.19 $image
        }
        _ => {}
    }
}

# Extra convenience commands for Virsh and Libvirt.
def main [
    --version (-v) # Print version information
] {
    if ($version) {
        version
    }
}

# Create a virtual machine from a cdrom or disk file.
def "main install" [
    --default: string # Download disk for domain and install with defaults
    --domain (-d): string # Virtual machine name
    --osinfo (-o): string = "generic" # Virt-install osinfo
    --password (-p): string # Cloud init password
    --username (-u): string # Cloud init username
    path?: string
] {
    if ($default | is-not-empty) {
        install_default $default
    } else if ($path | is-empty) {
        error make {
            help: "Run 'virshx install --help' for usage."
            label: { span: (metadata $path).span text: "" }
            msg: "Missing disk path positional argument"
        }
    }

    # # Check if domain is already used by libvirt.
    # if (virsh list --all --name | str contains $domain) {
    #     print --stderr "error: Domain is already in use"
    #     exit 1
    # }

    # let extension = $path | path parse | get extension
    # match $extension {
    #     "iso" => { install_cdrom $domain $osinfo $path }
    #     "img" | "qcow2" | "raw" | "vmdk" => {
    #         install_disk $domain $osinfo $path $extension $username $password
    #     }
    #     _ => {
    #         print --stderr "error: Unsupported extension '$extension'"
    #         exit 1
    #     }
    # }

    create_app $domain
}

# Configure machine for emulation.
def "main setup" [] {}

# Configure host machine.
def "main setup desktop" [] {
    let home = get_home

    (
        mkdir
        $"($home)/.virshx"
        $"($home)/.local/share/libvirt/cdroms"
        $"($home)/.local/share/libvirt/images"
    )

    let icon_path = $"($home)/.virshx/waveform.svg"
    if not ($icon_path | path exists) {
        http get "https://raw.githubusercontent.com/phosphor-icons/core/main/assets/regular/waveform.svg"
        | save $icon_path
    }

    let key_path = $"($home)/.virshx/key"
    if not ($key_path | path exists) {
        ssh-keygen -N '' -q -f $key_path -t ed25519 -C virshx
        chmod 600 $key_path $"($key_path).pub"
    }
}

def version [] {
    "Virshx 0.0.1"
}
