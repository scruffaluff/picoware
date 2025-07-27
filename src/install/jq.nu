#!/usr/bin/env nu

# Find command to elevate as super user.
def find-super [] {
    if (is-admin) {
        ""
    } else if $nu.os-info.name == "windows" {
        error make { msg: ("
System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
" | str trim)
        }
    } else if (which doas | is-not-empty) {
        "doas"
    } else if (which sudo | is-not-empty) {
        "sudo"
    } else {
        error make { msg: "Unable to find a command for super user elevation." }
    }
}

# Print message if error or logging is enabled.
def --wrapped log [...args: string] {
    if (
        not ($env.SCRIPTS_NOLOG? | into bool --relaxed)
        and not ("-e" in $args) and not ("--stderr" in $args)
    ) {
        print ...$args
    }
}

# Install program to destination folder.
def install [super: string dest: string subpath: string] {
    let quiet = $env.SCRIPTS_NOLOG? | into bool --relaxed
    let arch = match $nu.os-info.arch {
        "x86_64" => "amd64"
        "aarch64" => "arm64"
        _ => $nu.os-info.arch
    }
    let target = $"jq-($nu.os-info.name)-($arch)"
    let ext = if $nu.os-info.name == "windows" { ".exe" } else { "" }

    let temp = mktemp --directory --tmpdir
    let program = $"($temp)/jq($ext)"
    let uri = $"https://github.com/jqlang/jq/releases/($subpath)/($target)($ext)"
    if $quiet {
        http get $uri | save $program
    } else {
        http get $uri | save --progress $program
    }
    if $nu.os-info.name != "windows" {
        chmod +x $program
    }

    if ($super | is-empty) {
        mkdir $dest
        mv $program $"($dest)/($program | path basename)"
    } else {
        ^$super mkdir -p $dest
        ^$super mv $program $"($dest)/($program | path basename)"
    }
}

# Check if super user elevation is required.
def need-super [$dest: string, global: bool] {
    if $global {
        return true
    }
    try { mkdir $dest } catch { return true }
    try { touch $"($dest)/.super_check" } catch { return true }
    rm $"($dest)/.super_check" 
    false
}

# Install Jq for MacOS, Linux, and Windows systems.
def main [
    --dest (-d): string # Directory to install Jq
    --global (-g) # Install Jq for all users
    --preserve-env (-p) # Do not update system environment
    --quiet (-q) # Print only error messages
    --version (-v): string # Version of Jq to install
] {
    if $quiet { $env.SCRIPTS_NOLOG = "true" }
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

    let system = need-super $dest $global
    let super = if ($system) { find-super } else { "" }
    let subpath = if $version == null {
        "latest/download"
    } else {
        $"download/jq-($version)"
    }

    log $"Installing Jq to '($dest)'."
    install $super $dest $subpath
    if not $preserve_env and not ($dest in $env.PATH) {
        if $nu.os-info.name == "windows" {
            update-path $dest $system
        } else {
            update-shell $dest
        }
    }

    $env.PATH = $env.PATH | prepend $dest
    log $"Installed (jq --version)."
}

# Add destination path to Windows environment path.
def update-path [$dest: string, global: bool] {
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
def update-shell [dest: string] {
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
    log $"Added '($command)' to the '($profile)' shell profile."
    log "Source shell profile or restart shell after installation."
}
