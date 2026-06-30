#!/usr/bin/env nu

# Capitalize app name.
def capitalize [name: string] {
    $name | str replace '_' ' '
    | split row ' '
    | each { $in | str capitalize }
    | str join ' '
}

# Create application entrypoint script.
def create-entry [super: string script: path folder: string entry_path: path] {
    let shebang = open --raw $script | lines | first
    let command = $shebang | str replace "#!/usr/bin/env -S " "" | str replace "#!/usr/bin/env " ""
    let script_name = $script | path basename

    let text = $"
#!/usr/bin/env sh
set -eu

# Add interpreter to system path.
export PATH=\"($folder):${PATH}\"
# Resolve symlinks to find script folder.
folder=\"$\(dirname \"$\(realpath \"${0}\"\)\"\)\"
# Use interpeter to avoid env shebang conflicts.
exec '($command)' \"${folder}/($script_name)\" \"\$@\"
"
    | str trim
    | save --force $entry_path
    if ($super | is-empty) {
        chmod +rx $entry_path
    } else {
        ^$super chmod +x $entry_path
    }
}

# Copy and configure file.
def deploy [
    --mode (-m): string
    --super (-s): string
    source: string
    dest: string
] {
    let quiet = $env.SCRIPTS_NOLOG? | into bool --relaxed
    let folder = $dest | path dirname

    # Download to temporary file to avoid permission restrictions.
    let file = if ($source | path exists) {
        $source
    } else {
        let temp = mktemp --tmpdir
        if $quiet {
            http get $source | save --force $temp
        } else {
            http get $source | save --force --progress $temp
        }
        $temp
    }

    # Copy file instead of move to ensure correct ownership.
    if ($super | is-empty) {
        mkdir $folder
        cp $file $dest
        if ($mode | is-not-empty) and $nu.os-info.name != "windows" {
            chmod $mode $dest
        }
    } else {
        ^$super mkdir -p $folder
        ^$super cp $file $dest
        if ($mode | is-not-empty) and $nu.os-info.name != "windows" {
            ^$super chmod $mode $dest
        }
    }
}

# Download application from repository.
def fetch-app [super: string version: string name: string dest: directory] {
    let url = $"https://raw.githubusercontent.com/scruffaluff/picoware/refs/heads/($version)/src/app/($name)"
    let files = http get $"https://api.github.com/repos/scruffaluff/picoware/git/trees/($version)?recursive=true"
        | get tree
        | where type == blob
        | get path
        | where {|path| ($path | str starts-with $"src/app/($name)/") }
        | each {|path| $path | str replace $"src/app/($name)/" "" }

    if ($super | is-empty) {
        mkdir $dest
    } else {
        ^$super mkdir -p $dest
    }

    mut script = ""
    for file in $files {
        let dest_file = $dest | path join $file
        let ext = $file | path parse | get extension

        if $ext in ["nu" "ps1" "py" "rs" "sh" "ts"] {
            if ($file | path parse | get stem) == "main" {
                $script = $dest_file
            }
            deploy --mode 755 --super $super $"($url)/($file)" $dest_file
        } else {
            deploy --super $super $"($url)/($file)" $dest_file
        }
    }

    $script
}

# Find all apps inside repository.
def find-apps [version: string = "main"] {
    if ($version | path exists) {
        ls $"($version)/src/app" | get name | each {|name| $name | path basename }
    } else {
        http get $"https://api.github.com/repos/scruffaluff/picoware/git/trees/($version)?recursive=true"
        | get tree
        | where type == tree
        | get path
        | where {|path| ($path | str starts-with "src/app/") }
        | each {|path| $path | str replace "src/app/" "" }
    }
}

# Find application runner.
def find-runner [super: string script: path] {
    let ext = $script | path parse | get extension
    match $ext {
        nu => {
            which nu | first
        }
        py => {
            if (which uv | is-empty) {
                mut args = ["--quiet" "--preserve-env"]
                if ($super | is-not-empty) {
                    $args = [...$args "--global"]
                }
                http get https://scruffaluff.github.io/picoware/install/uv.nu
                | nu -c $"($in | decode); main ($args | str join ' ')"
            }
            which uv | first
        }
        rs => {
            if (which rust-script | is-empty) {
                mut args = ["--quiet" "--preserve-env"]
                if ($super | is-not-empty) {
                    $args = [...$args "--global"]
                }
                http get https://scruffaluff.github.io/picoware/install/rust-script.nu
                | nu -c $"($in | decode); main ($args | str join ' ')"
            }
            which rust-script | first
        }
        ts => {
            if (which deno | is-empty) {
                mut args = ["--quiet" "--preserve-env"]
                if ($super | is-not-empty) {
                    $args = [...$args "--global"]
                }
                http get https://scruffaluff.github.io/picoware/install/deno.nu
                | nu -c $"($in | decode); main ($args | str join ' ')"
            }
            which deno | first
        }
        _ => {
            error make $"Unable to find an application runner for ($script)."
        }
    }
}

# Find command to elevate as super user.
def find-super [] {
    if (is-admin) {
        ""
    } else if $nu.os-info.name == "windows" {
        error make ("
System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
        " | str trim)
    } else if (which doas | is-not-empty) {
        "doas"
    } else if (which sudo | is-not-empty) {
        "sudo"
    } else {
        error make "Unable to find a command for super user elevation."
    }
}

# Install application for Linux.
def install-app-linux [super: string version: string name: string dest: directory] {
    let url = $"https://raw.githubusercontent.com/scruffaluff/picoware/refs/heads/($version)"
    let title = capitalize $name

    let cli_dir = if ($super | is-not-empty) {
        "/usr/local/bin"
    } else {
        $"($env.HOME)/.local/bin"
    }
    let app_dest = $"($dest)/($name)"
    let manifest = if ($super | is-not-empty) {
        "/usr/local/share/applications/($name).desktop"
    } else {
        $"($env.HOME)/.local/share/applications/($name).desktop"
    }
    let entry_point = $"($app_dest)/main.sh"
    let icon = $"($app_dest)/icon.svg"

    log $"Installing application ($title)."
    deploy --super $super $"($url)/data/image/icon.svg" $icon
    let script = fetch-app $super $version $name $app_dest
    let runner = find-runner $super $script
    create-entry $super $script ($runner | path dirname) $entry_point
    if ($super | is-empty) {
        symlink $entry_point $"($cli_dir)/($name)"
    } else {
        ^$super ln -fs $entry_point $"($cli_dir)/($name)"
    }

    # Parse window class to ensure correct dock icon.
    let wmclass = match ($runner | path basename) {
        deno => "GTK Application"
        rust-script => "GTK Application"
        uv => "python3"
        _ => ""
    }

    $"
[Desktop Entry]
Exec=($entry_point)
Icon=($icon)
Name=($title)
StartupWMClass=($wmclass)
Terminal=false
Type=Application
"
    | if ($super | is-empty) {
        save --force $manifest
    } else {
        ^$super tee $manifest > /dev/null
    }

    if ($super | is-empty) {
        update-desktop-database ($manifest | path dirname)
    } else {
        ^$super update-desktop-database ($manifest | path dirname)
    }

    # Update shell profile if CLI is not in system path.
    if not ($cli_dir in $env.PATH) {
        update-shell $cli_dir
    }

    $env.PATH = [$cli_dir ...$env.PATH]
    log $"Installed (^$name --version | str trim)."
}

# Install application for MacOS.
def install-app-macos [super: string version: string name: string dest: directory] {
    let url = $"https://raw.githubusercontent.com/scruffaluff/picoware/refs/heads/($version)"
    let title = capitalize $name
    let identifier = $"com.scruffaluff.app-($name | str replace '_' '-')"

    let cli_dir = if ($super | is-not-empty) {
        "/usr/local/bin"
    } else {
        $"($env.HOME)/.local/bin"
    }
    let app_dest = $"($dest)/($name)"
    let icon = if ($super | is-not-empty) {
        $"/Applications/($title).app/Contents/Resources/icon.icns"
    } else {
        $"($env.HOME)/Applications/($title).app/Contents/Resources/icon.icns"
    }
    let manifest = if ($super | is-not-empty) {
        $"/Applications/($title).app/Contents/Info.plist"
    } else {
        $"($env.HOME)/Applications/($title).app/Contents/Info.plist"
    }
    let entry_point = $"($app_dest)/main.sh"

    log $"Installing application ($title)."
    deploy --super $super $"($url)/data/image/icon.icns" $icon
    let script = fetch-app $super $version $name $app_dest
    let runner = find-runner $super $script
    create-entry $super $script ($runner | path dirname) $entry_point
    if ($super | is-empty) {
        symlink $entry_point $"($cli_dir)/($name)"
    } else {
        ^$super ln -fs $entry_point $"($cli_dir)/($name)"
    }

    $"
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleDisplayName</key>
  <string>($title)</string>
  <key>CFBundleExecutable</key>
  <string>main.sh</string>
  <key>CFBundleIconFile</key>
  <string>icon.icns</string>
  <key>CFBundleIdentifier</key>
  <string>($identifier)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>($name)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CSResourcesFileMapped</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>10.13</string>
  <key>LSRequiresCarbon</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
"
    | if ($super | is-empty) {
        save --force $manifest
    } else {
        ^$super tee $manifest > /dev/null
    }

    # Update shell profile if CLI is not in system path.
    if not ($cli_dir in $env.PATH) {
        update-shell $cli_dir
    }

    $env.PATH = [$cli_dir ...$env.PATH]
    log $"Installed (^$name --version | str trim)."
}

# Install application for Windows.
def install-app-windows [system: bool version: string name: string dest: directory] {
    let url = $"https://raw.githubusercontent.com/scruffaluff/picoware/refs/heads/($version)"
    let title = capitalize $name

    let cli_dir = if $system {
        "C:\\Program Files\\Bin"
    } else {
        $"($env.LocalAppData)\\Programs\\Bin"
    }
    let app_dest = $"($dest)/($name)"
    let menu_dir = if $system {
        "C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\App"
    } else {
        $"($env.AppData)\\Microsoft\\Windows\\Start Menu\\Programs\\App"
    }

    log $"Installing application ($title)."
    deploy --super "" $"($url)/data/public/favicon.ico" $"($app_dest)/icon.ico"
    let script = fetch-app "" $version $name $app_dest
    setup-runner $name $script $app_dest $cli_dir $menu_dir $system

    # Update path variable if CLI is not in system path.
    if not ($cli_dir in $env.PATH) {
        update-path $cli_dir $system
    }

    $env.PATH = [$cli_dir ...$env.PATH]
    log $"Installed (^$name --version | str trim)."
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

# Installer script for Picoware apps.
def main [
    --dest (-d): directory # Directory to install apps
    --global (-g) # Install apps for all users
    --list (-l) # List all available apps
    --quiet (-q) # Print only error messages
    --version (-v): string = "main" # Version of apps to install
    ...apps: string # App names
] {
    if $quiet { $env.SCRIPTS_NOLOG = "true" }
    # Force global if root on Unix.
    let global = $global or ((is-admin) and $nu.os-info.name != "windows")

    let names = if $list {
        for app in (find-apps $version) {
            print ($app | path parse | get stem)
        }
        return
    } else if ($apps | is-empty) {
        log --stderr "error: App argument required."
        log --stderr "Run 'install-apps --help' for usage."
        exit 2
    } else {
        find-apps $version
    }

    let dest_default = if $nu.os-info.name == "windows" {
        if $global {
            "C:\\Program Files\\App"
        } else {
            $"($env.LocalAppData)\\Programs\\App"
        }
    } else {
        if $global { "/usr/local/app" } else { $"($env.HOME)/.local/app" }
    }
    let dest = $dest | default $dest_default | path expand

    let system = need-super $dest $global
    let super = if $system { find-super } else { "" }

    for app_name in $apps {
        mut match = false
        for app in $names {
            let stem = $app | path parse | get stem
            if $app_name == $stem {
                $match = true
                match $nu.os-info.name {
                    macos => { install-app-macos $super $version $app $dest }
                    windows => { install-app-windows $system $version $app $dest }
                    _ => { install-app-linux $super $version $app $dest }
                }
            }
        }

        if not $match {
            log --stderr $"error: No app found for '($app_name)'."
        }
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

# Create Windows runner for application.
def setup-runner [
    name: string
    script: path
    dest_dir: string
    cli_dir: string
    menu_dir: string
    global: bool
] {
    let title = capitalize $name
    let ext = $script | path parse | get extension
    let runner = match $ext {
        nu => {
            if (which nu | is-empty) {
                mut args = ["--quiet" "--preserve-env"]
                if $global {
                    $args = [...$args "--global"]
                }
                http get https://scruffaluff.github.io/picoware/install/nushell.ps1
                | powershell -command $"($in | Out-String) ($args | str join ' ')"
            }
            let runner = (which nu | first)
            $"nu \"$script\""
        }
        py => {
            if (which uv | is-empty) {
                mut args = ["--quiet" "--preserve-env"]
                if $global {
                    $args = [...$args "--global"]
                }
                http get https://scruffaluff.github.io/picoware/install/uv.ps1
                | powershell -command $"($in | Out-String) ($args | str join ' ')"
            }
            let runner = (which uv | first)
            $"uv --no-config --quiet run --script \"$script\""
        }
        rs => {
            if (which rust-script | is-empty) {
                mut args = ["--quiet" "--preserve-env"]
                if $global {
                    $args = [...$args "--global"]
                }
                http get https://scruffaluff.github.io/picoware/install/rust-script.ps1
                | powershell -command $"($in | Out-String) ($args | str join ' ')"
            }
            let runner = (which rust-script | first)
            $"rust-script \"$script\""
        }
        ts => {
            if (which deno | is-empty) {
                mut args = ["--quiet" "--preserve-env"]
                if $global {
                    $args = [...$args "--global"]
                }
                http get https://scruffaluff.github.io/picoware/install/deno.ps1
                | powershell -command $"($in | Out-String) ($args | str join ' ')"
            }
            let runner = (which deno | first)
            $"deno run --allow-all --no-config --quiet --node-modules-dir=none \"$script\""
        }
        ps1 => {
            let runner = (which powershell | first)
            $"powershell -NoProfile -ExecutionPolicy RemoteSigned -File \"$script\""
        }
        _ => {
            let runner = (which powershell | first)
            $"powershell -NoProfile -ExecutionPolicy RemoteSigned -File \"$script\""
        }
    }

    let cmd_content = $"@echo off\n($runner) %*\n"
    $cmd_content | save --force $"($cli_dir)/($name).cmd"

    # Create start menu shortcut via PowerShell.
    let ps_script = $"
\$WshShell = New-Object -ComObject WScript.Shell
\$Shortcut = \$WshShell.CreateShortcut('($menu_dir)/($title).lnk')
\$Shortcut.Arguments = '($runner)'
\$Shortcut.IconLocation = '($dest_dir)/icon.ico'
\$Shortcut.TargetPath = '($runner)'
\$Shortcut.WindowStyle = 7
\$Shortcut.Save()
    d"
    powershell -command $ps_script
}

# Add destination path to Windows environment path.
def update-path [dest: directory global: bool] {
    let target = if $global { "Machine" } else { "User" }
    powershell -command $"
$Dest = '($dest | path expand)'
$Path = [Environment]::GetEnvironmentVariable\('Path', '($target)'\)
if \(-not \($Path -like \"*$Dest*\"\)\) {{
    $PrependedPath = \"$Dest;$Path\"
    [System.Environment]::SetEnvironmentVariable\(
        'Path', \"$PrependedPath\", '($target)'
    \)
    Write-Output \"Added '$Dest' to the system path.\"
    Write-Output 'Source shell profile or restart shell after installation.'
}}
"
}

# Add script to system path in shell profile.
def update-shell [dest: directory] {
    let shell = $env.SHELL? | default "" | path basename

    let command = match $shell {
        fish => $"set --export PATH \"($dest)\" $PATH"
        nu => $"$env.PATH = [\"($dest)\" ...$env.PATH]"
        _ => $"export PATH=\"($dest):${{PATH}}\""
    }
    let profile = match $shell {
        bash => $"($env.HOME)/.bashrc"
        fish => "($env.HOME)/.config/fish/config.fish"
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
