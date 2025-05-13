#!/usr/bin/env nu

# Find command to elevate as super user.
def find_super [] {
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

# Check if super user elevation is required.
def need_super [$dest: string, global: bool] {
    if $global {
        return true
    }
    try { mkdir $dest } catch { return true }
    try { touch $"($dest)/.super_check" } catch { return true }
    rm $"($dest)/.super_check" 
    false
}

# Install Deno for MacOS, Linux, and Windows systems.
def main [
    --dest (-d): string # Directory to install Deno
    --global (-g) # Install Deno for all users
    --preserve-env (-p) # Do not update system environment
    --quiet (-q) # Print only error messages
    --version (-v): string # Version of Deno to install
] {
    let arch = $nu.os-info.arch
    let target = match $nu.os-info.name {
        "linux" => $"($nu.os-info.arch)-unknown-linux-gnu"
        "macos" => $"($nu.os-info.arch)-apple-darwin"
        "windows" => $"($nu.os-info.arch)-pc-windows-msvc"
    }

    let dest_default = if $nu.os-info.name == "windows" {
        if $global {
            "C:\\Program Files\\Bin"
        } else {
            $"($env.LOCALAPPDATA)\\Programs\\Bin"
        }
    } else {
        if $global { "/usr/local/bin" } else { $"($env.HOME)/.local/bin" }
    }
    let dest = $dest | default $dest_default | path expand

    let system = need_super $dest $global
    let super = if ($system) { find_super } else { "" }
    let version_ = $version
    | default (http get https://dl.deno.land/release-latest.txt)
    
    if (which unzip | is-empty) {
        print --stderr 'error: Unable to find zip file archiver.'
        print --stderr 'Install zip, https://en.wikipedia.org/wiki/ZIP_(file_format), manually before continuing.'
        exit 1
    }

    print $"Installing Deno to '($dest)'."
    let temp = mktemp --directory --tmpdir
    http get $"https://dl.deno.land/release/($version_)/deno-($target).zip"
    | save --progress $"($temp)/deno.zip"
    unzip -d $temp $"($temp)/deno.zip"

    let program = if $nu.os-info.name == "windows" {
        "deno.exe"
    } else {
        "deno"
    }

    if ($super | is-empty) {
        mkdir $dest
        mv $"($temp)/($program)" $"($dest)/($program)"
    } else {
        ^$super mkdir -p $dest
        ^$super mv $"($temp)/($program)" $"($dest)/($program)"
    }

    if not $preserve_env and not ($dest in $env.PATH) {
        if $nu.os-info.name == "windows" {
            update_path $dest $system
        } else {
            update_shell $dest
        }
    }

    $env.PATH = $env.PATH | prepend $dest
    print $"Installed (deno --version)."
}

# Wrapper to handle conditional prefix commands.
def --wrapped runsup [super: string ...args] {
    # Quote all parameters to Nushell commands to support paths with spaces.
    let args = [$args.0 ...($args | skip 1 | each {|arg| $"'($arg)'" })]
    if ($super | is-empty) {
        nu --stdin --commands $"($args | str join ' ')"
    } else {
        ^$super nu --stdin --commands $"($args | str join ' ')"
    }
}

# Add destination path to Windows environment path.
def update_path [$dest: string, global: bool] {
    let target = if $global { "Machine" } else { "User" }
    powershell -command $"
$Path = [Environment]::GetEnvironmentVariable\('Path', '($target)'\)
if \(-not \($Path -like \"*($dest)*\"\)\) {
    $PrependedPath = \"($dest);$Path\"
    [System.Environment]::SetEnvironmentVariable\(
        'Path', \"$PrependedPath\", '($target)'
    \)
    Write-Output \"Added '($dest)' to the system path.\"
    Write-Output 'Source shell profile or restart shell after installation.'
}
"
}

# Add script to system path in shell profile.
def update_shell [dest: string] {
    let shell = $env.SHELL? | default "" | path basename

    let command = match $shell {
        "fish" => $"set --export PATH \"($dest)\" $PATH"
        "nu" => $"$env.PATH = [\"($dest)\" ...$env.PATH]"
        _ => $"export PATH=\"($dest):${PATH}\""
    }
    let profile = match $shell {
        "bash" => $"($env.HOME)/.bashrc"
        "fish" => "($env.HOME)/.config/fish/config.fish"
        "nu" => {
            if $nu.os-info.name == "macos" {
                $"($env.HOME)/Library/Application Support/nushell/config.nu"
            } else {
                $"$(env.HOME)/.config/nushell/config.nu"
            }
        }
        "zsh" => $"($env.HOME)/.zshrc"
        _ => $"($env.HOME)/.profile"
    }

    # Create profile parent directory and add export command to profile
    mkdir ($profile | path dirname)
    $"\n# Added by Scripts installer.\n($command)\n" | save --append $profile
    print $"Added '($command)' to the '($profile)' shell profile."
    print "Source shell profile or restart shell after installation."
}
