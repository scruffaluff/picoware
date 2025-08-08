#!/usr/bin/env nu

# Ensure script dependencies are available.
def check-deps [] {
    if $nu.os-info.name != "windows" and (which tar | is-empty) {
        error make { msg: ("
error: Unable to find tar file archiver.
Install tar, https://www.gnu.org/software/tar, manually before continuing.
"
            | str trim)
        }
    }
}

# Find command to elevate as super user.
def find-super [] {
    if (is-admin) {
        ""
    } else if $nu.os-info.name == "windows" {
        error make { msg: ("
System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
"
            | str trim)
        }
    } else if (which doas | is-not-empty) {
        "doas"
    } else if (which sudo | is-not-empty) {
        "sudo"
    } else {
        error make { msg: "Unable to find a command for super user elevation." }
    }
}

# Install program to destination folder.
def install [super: string dest: directory version: string] {
    let quiet = $env.SCRIPTS_NOLOG? | into bool --relaxed
    let archive = if $nu.os-info.name == "windows" { ".zip" } else { ".tar.gz" }
    let target = match $nu.os-info.name {
        "linux" => $"uv-($nu.os-info.arch)-unknown-linux-musl"
        "macos" => $"uv-($nu.os-info.arch)-apple-darwin"
        "windows" => $"uv-($nu.os-info.arch)-pc-windows-msvc"
    }

    let temp = mktemp --directory --tmpdir
    let uri = $"https://github.com/astral-sh/uv/releases/download/($version)/($target)($archive)"
    if $quiet {
        http get $uri | save $"($temp)/uv($archive)"
    } else {
        http get $uri | save --progress $"($temp)/uv($archive)"
    }

    let program = if $nu.os-info.name == "windows" {
        powershell -command $"
$ProgressPreference = 'SilentlyContinue'
Expand-Archive -DestinationPath '($temp)' -Path '($temp)/uv.zip'
"
        $"($temp)/uv.exe"
    } else {
        tar fx $"($temp)/uv.tar.gz" -C $temp
        $"($temp)/($target)/uv"
    }

    let dest_file = $"($dest)/($program | path basename)"
    if ($super | is-empty) {
        mkdir $dest
        cp $program $dest_file
        if $nu.os-info.name != "windows" {
            chmod 755 $dest_file
        }
    } else {
        ^$super mkdir -p $dest
        ^$super cp $program $dest_file
        if $nu.os-info.name != "windows" {
            sudo chmod 755 $dest_file
        }
    }
}

# Print message if error or logging is enabled.
def --wrapped log [...args: string] {
    if (
        not ($env.SCRIPTS_NOLOG? | into bool --relaxed)
        or ("-e" in $args) or ("--stderr" in $args)
    ) {
        print ...$args
    }
}

# Check if super user elevation is required.
def need-super [dest: directory global: bool] {
    if $global {
        return true
    }
    try { mkdir $dest } catch { return true }
    try { touch $"($dest)/.super_check" } catch { return true }
    rm $"($dest)/.super_check" 
    false
}

# Install Uv for MacOS, Linux, and Windows systems.
def main [
    --dest (-d): directory # Directory to install Uv
    --global (-g) # Install Uv for all users
    --preserve-env (-p) # Do not update system environment
    --quiet (-q) # Print only error messages
    --version (-v): string # Version of Uv to install
] {
    if $quiet { $env.SCRIPTS_NOLOG = "true" }
    # Force global if root on Unix.
    let global = $global or ((is-admin) and $nu.os-info.name != "windows")

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

    check-deps
    let system = need-super $dest $global
    let super = if ($system) { find-super } else { "" }
    let version = $version | default (
        http get "https://formulae.brew.sh/api/formula/uv.json"
        | get versions.stable
    )

    log $"Installing Uv to '($dest)'."
    install $super $dest $version
    if not $preserve_env and not ($dest in $env.PATH) {
        if $nu.os-info.name == "windows" {
            update-path $dest $system
        } else {
            update-shell $dest
        }
    }

    $env.PATH = $env.PATH | prepend $dest
    log $"Installed (uv --version)."
}

# Add destination path to Windows environment path.
def update-path [dest: directory global: bool] {
    let target = if $global { "Machine" } else { "User" }
    powershell -command $"
$Dest = '($dest | path expand)'
$Path = [Environment]::GetEnvironmentVariable\('Path', '($target)'\)
if \(-not \($Path -like \"*$Dest*\"\)\) {
    $PrependedPath = \"$Dest;$Path\"
    [System.Environment]::SetEnvironmentVariable\(
        'Path', \"$PrependedPath\", '($target)'
    \)
    Write-Output \"Added '$Dest' to the system path.\"
    Write-Output 'Source shell profile or restart shell after installation.'
}
"
}

# Add script to system path in shell profile.
def update-shell [dest: directory] {
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
