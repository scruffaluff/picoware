#!/usr/bin/env -S nu --no-config-file --stdin

# Find all installable scripts inside repository.
def find-scripts [version: string = "main"] {
    let exts = if $nu.os-info.name == "windows" {
        [".nu" ".ps1" ".py" ".rs" ".ts"]
    } else {
        [".nu" ".py" ".rs" ".sh" ".ts"]
    }

    http get $"https://api.github.com/repos/scruffaluff/scripts/git/trees/($version)?recursive=true"
    | get tree | where type == blob | get path
    | where {|path| ($path | str starts-with "src/script/") and (
            $exts | reduce --fold false {
                |ext, acc| $acc or ($path | str ends-with $ext)
            }
        )
    }
    | each {|path| $path | path basename }
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

# Create entrypoint script if necessary.
def handle-shebang [super: string path: path extension: string] {
    let split_env = "#!/usr/bin/env -S "
    let shebang = open --raw $path | lines | first
    let script = $"($path).($extension)"

    # Exit early if `env` can handle the shebang arguments.
    if ($shebang | str contains $split_env) {
        let result = /usr/bin/env -S echo test | complete
        if $result.exit_code == 0 { return }
    } else {
        return
    }

    # Add entrypoint replacement for script.
    let command = $shebang | str replace "#!/usr/bin/env -S " ""
    let temp = mktemp --tmpdir
    $"
#!/usr/bin/env sh
set -eu

exec ($command) '($script)' \"$@\"
"
    | str trim --left | save --force $temp
    chmod +rx $temp

    # Move script to new location.
    if ($super | is-empty) {
        mv $path $script
        mv $temp $path
        chmod -x $script
    } else {
        ^$super cp $path $script
        ^$super cp $temp $path
        ^$super chmod -x $script
    }
}

# Install script to destination folder.
def install-script [
    super: string
    system: bool
    preserve_env: bool
    version: string
    dest: directory
    script: string
] {
    let quiet = $env.SCRIPTS_NOLOG? | into bool --relaxed
    let parts = $script | path parse
    let ext = $parts | get extension
    let name = $parts | get stem

    mut args = []
    if $preserve_env {
        $args = [...$args "--preserve-env"]
    }
    if $system {
        $args = [...$args "--global"]
    }
    if $ext == "py" and (which uv | is-empty) {
        http get https://scruffaluff.github.io/scripts/install/uv.nu
        | nu -c $"($in | decode); main --quiet ($args | str join ' ')"
    } else if $ext == "ts" and (which deno | is-empty) {
        http get https://scruffaluff.github.io/scripts/install/deno.nu
        | nu -c $"($in | decode); main --quiet ($args | str join ' ')"
    }

    let program = if $nu.os-info.name == "windows" {
        $"($dest)/($script)"
    } else {
        $"($dest)/($name)"
    }

    log $"Installing script ($script) to '($program)'."
    let temp = mktemp --tmpdir
    let uri = $"https://raw.githubusercontent.com/scruffaluff/scripts/($version)/src/script/($script)"
    if $quiet {
        http get $uri | save --force $temp
    } else {
        http get $uri | save --force --progress $temp
    }

    if $nu.os-info.name == "windows" {
        install-wrapper $ext $"($dest)/($name)"
    } else {
        chmod +rx $temp
    }
    if ($super | is-empty) {
        mkdir $dest
        mv $temp $program
    } else {
        ^$super mkdir -p $dest
        ^$super cp $temp $program
    }

    if $nu.os-info.name != "windows" {
        handle-shebang $super $program $ext
    }
    if not $preserve_env and not ($dest in $env.PATH) {
        if $nu.os-info.name == "windows" {
            update-path $dest $system
        } else {
            update-shell $dest
        }
    }

    $env.PATH = [$dest ...$env.PATH]
    let version = ^$name --version
    log $"Installed ($version)."
}

# Install wrapper script for Windows.
def install-wrapper [ext: string dest: path] {
    let wrapper = match $ext {
        "nu" => 'nu "%~dnp0.nu" %*'
        "ps1" => 'powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%~dnp0.ps1" %*'
        "py" => 'uv --no-config run --script "%~dnp0.py" %*'
        "ts" => 'deno run --allow-all "%~dnp0.ts" %*'
    }
    
    $"@echo off\n($wrapper)\n" | save --force $"($dest).cmd"
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

# Installer script for Scripts.
def main [
    --dest (-d): directory # Directory to install scripts
    --global (-g) # Install scripts for all users
    --list (-l) # List all available scripts
    --preserve-env (-p) # Do not update system environment
    --quiet (-q) # Print only error messages
    --version (-v): string = "main" # Version of scripts to install
    ...scripts: string # Scripts names
] {
    if $quiet { $env.SCRIPTS_NOLOG = "true" }
    # Force global if root on Unix.
    let global = $global or ((is-admin) and $nu.os-info.name != "windows")

    let names = if $list {
        for script in (find-scripts $version) {
            print ($script | path parse | get stem)
        }
        return
    } else if ($scripts | is-empty) {
        log --stderr "error: Script argument required."
        log --stderr "Run 'install-scripts --help' for usage."
        exit 2
    } else {
        find-scripts $version
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

    let system = need-super $dest $global
    let super = if ($system) { find-super } else { "" }

    for script in $scripts {
        mut match = false
        for name in $names {
            let stem = $name | path parse | get stem
            if $script == $stem {
                $match = true
                install-script $super $system $preserve_env $version $dest $name
            }
        }
        
        if not $match {
            log --stderr $"error: No script found for '($script)'."
        }
    }
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
