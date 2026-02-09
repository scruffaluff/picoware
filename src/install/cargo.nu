#!/usr/bin/env nu

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

# Print message if error or logging is enabled.
def --wrapped log [...args: string] {
    if (
        not ($env.SCRIPTS_NOLOG? | into bool --relaxed)
        or ("-e" in $args) or ("--stderr" in $args)
    ) {
        print ...$args
    }
}

# Install program to destination folder for Unix
def install-cargo-unix [super: string dest: directory version: string] {
    let quiet = $env.SCRIPTS_NOLOG? | into bool --relaxed
    let parts = $dest | path parse
    let rustup_home = if ($parts | get stem | str starts-with ".") {
        $"($parts.parent)/.rustup"
    } else {
        $"($parts.parent)/rustup"
    }

    mut args = ["-y" "--no-modify-path" "--profile" "minimal"]
    if $quiet {
        $args = [...$args "--quiet"]
    }
    if ($version | is-not-empty) {
        $args = [...$args "--default-toolchain" $version]
    }
    let args = $args

    with-env {
        CARGO_HOME: $dest
        PATH: [$"($dest)/bin" ...$env.PATH]
        RUSTUP_HOME: $rustup_home
    } {
        if ($super | is-empty) {
            http get https://sh.rustup.rs | sh -s -- ...$args
        } else {
            http get https://sh.rustup.rs | ^$super -E sh -s -- ...$args
        }
    }
}

# Install program to destination folder for Windows.
def install-cargo-windows [dest: directory version: string] {
    let quiet = $env.SCRIPTS_NOLOG? | into bool --relaxed
    let parts = $dest | path parse
    let rustup_home = if ($parts | get stem | str starts-with ".") {
        $"($parts.parent)\\.rustup"
    } else {
        $"($parts.parent)\\rustup"
    }

    mut args = ["-y" "--no-modify-path" "--profile" "minimal"]
    if $quiet {
        $args = [...$args "--quiet"]
    }
    if ($version | is-not-empty) {
        $args = [...$args "--default-toolchain" $version]
    }
    let args = $args

    let temp = mktemp --directory --tmpdir
    let uri = $"https://static.rust-lang.org/rustup/dist/($nu.os-info.arch)-pc-windows-msvc/rustup-init.exe"
    if $quiet {
        http get $uri | save $"($temp)\\rustup-init.exe"
    } else {
        http get $uri | save --progress $"($temp)\\rustup-init.exe"
    }

    with-env {
        CARGO_HOME: $dest
        PATH: [$"($dest)\\bin" ...$env.PATH]
        RUSTUP_HOME: $rustup_home
    } {
        ^$"($temp)\\rustup-init.exe" ...$args
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

# Install Cargo for MacOS, Linux, and Windows systems.
def main [
    --dest (-d): directory # Directory to install Cargo
    --global (-g) # Install Cargo for all users
    --preserve-env (-p) # Do not update system environment
    --quiet (-q) # Print only error messages
    --version (-v): string # Version of Cargo to install
] {
    if $quiet { $env.SCRIPTS_NOLOG = "true" }
    # Force global if root on Unix.
    let global = $global or ((is-admin) and $nu.os-info.name != "windows")

    let dest_default = if $nu.os-info.name == "windows" {
        if $global {
            "C:\\Program Files\\cargo"
        } else {
            $"($env.LocalAppData)\\cargo"
        }
    } else {
        if $global { "/usr/local/cargo" } else { $"($env.HOME)/.cargo" }
    }
    let dest = $dest | default $dest_default | path expand
    let bin = $dest | path join "bin"

    let system = need-super $dest $global
    let super = if ($system) { find-super } else { "" }

    log $"Installing Cargo to '($dest)'."
    if $nu.os-info.name == "windows" {
        install-cargo-windows $dest $version
        if not $preserve_env and not ($bin in $env.PATH) {
            update-path $bin $system
        }
    } else {
        install-cargo-unix $super $dest $version
        if not $preserve_env and not ($bin in $env.PATH) {
            update-shell $bin
        }
    }

    $env.PATH = $env.PATH | prepend $bin
    log $"Installed (cargo --version)."
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
                $"($env.HOME)/.config/nushell/config.nu"
            }
        }
        "zsh" => $"($env.HOME)/.zshrc"
        _ => $"($env.HOME)/.profile"
    }

    # Create profile parent directory and add export command to profile
    mkdir ($profile | path dirname)
    $"\n# Added by Picoware installer.\n($command)\n" | save --append $profile
    log $"Added '($command)' to the '($profile)' shell profile."
    log "Source shell profile or restart shell after installation."
}
