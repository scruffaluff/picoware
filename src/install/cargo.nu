#!/usr/bin/env nu

# Install program to destination folder for Unix
def install-cargo-unix [dest: directory version?: string] {
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

    log $"Installing Cargo to '($dest)/bin/cargo'."
    with-env {
        CARGO_HOME: $dest
        PATH: [$"($dest)/bin" ...$env.PATH]
        RUSTUP_HOME: $rustup_home
    } {
        http get https://sh.rustup.rs | sh -s -- ...$args
    }
}

# Install program to destination folder for Windows.
def install-cargo-windows [dest: directory version?: string] {
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

    log $"Installing Cargo to '($dest)\\bin\\cargo.exe'."
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

# Print message if error or logging is enabled.
def --wrapped log [
    --stderr (-e) # Print to stderr instead of stdout
    ...args: string
] {
    if $stderr {
        print --stderr ...$args
    } else if not ($env.SCRIPTS_NOLOG? | into bool --relaxed) {
        print ...$args
    }
}

# Check if super user elevation is required.
def need-super [dest: directory] {
    try { mkdir $dest } catch { return true }
    try { touch $"($dest)/.super_check" } catch { return true }
    rm $"($dest)/.super_check"
    false
}

# Install Cargo for MacOS, Linux, and Windows systems.
def main [
    --dest (-d): directory # Directory to install Cargo
    --preserve-env (-p) # Do not update system environment
    --quiet (-q) # Print only error messages
    --version (-v): string # Version of Rust to install
] {
    if $quiet { $env.SCRIPTS_NOLOG = "true" }
    let dest = $dest | default $"(path-home)/.cargo" | path expand
    let bin = $dest | path join "bin"

    # Check if admin permissions are required since rustup cannot be installed
    # globally.
    if ($nu.os-info.name != "windows" and (is-admin)) or (need-super $dest) {
        error make "Cargo cannot be installed with admin permissions."
    }

    if $nu.os-info.name == "windows" {
        install-cargo-windows $dest $version
        if not $preserve_env and not ($bin in $env.PATH) {
            update-path $bin
        }
    } else {
        install-cargo-unix $dest $version
        if not $preserve_env and not ($bin in $env.PATH) {
            update-shell $bin
        }
    }

    $env.PATH = $env.PATH | prepend $bin
    log $"Installed (cargo --version)."
}

# Get user home folder.
def path-home [] {
    if $nu.os-info.name == "windows" {
        $env.HOME? | default $"($env.HOMEDRIVE?)($env.HOMEPATH?)"
    } else {
        $env.HOME?
    }
}

# Add destination path to Windows environment path.
def update-path [dest: directory] {
    powershell -command $"
$Dest = '($dest | path expand)'
$Path = [Environment]::GetEnvironmentVariable\('Path', 'User'\)
if \(-not \($Path -like \"*$Dest*\"\)\) {
    $PrependedPath = \"$Dest;$Path\"
    [System.Environment]::SetEnvironmentVariable\(
        'Path', \"$PrependedPath\", 'User'
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
        fish => $"set --export PATH \"($dest)\" $PATH"
        nu => $"$env.PATH = [\"($dest)\" ...$env.PATH]"
        _ => $"export PATH=\"($dest):${PATH}\""
    }
    let profile = match $shell {
        bash => $"($env.HOME)/.bashrc"
        fish => $"($env.HOME)/.config/fish/config.fish"
        nu => {
            if $nu.os-info.name == "macos" {
                $"($env.HOME)/Library/Application Support/nushell/config.nu"
            } else {
                $"($env.HOME)/.config/nushell/config.nu"
            }
        }
        zsh => $"($env.HOME)/.zshrc"
        _ => $"($env.HOME)/.profile"
    }

    # Create profile parent directory and add export command to profile.
    mkdir ($profile | path dirname)
    $"\n# Added by Picoware installer.\n($command)\n" | save --append $profile
    log $"Added '($command)' to the '($profile)' shell profile."
    log "Source shell profile or restart shell after installation."
}
