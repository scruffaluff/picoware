#!/usr/bin/env nu

use std/log

# Capitalize application name.
def capitalize [name: string] {
    $name
    | str replace --regex "[_-]" " "
    | split words
    | str capitalize
    | str join " "
}

# Initialize application on Linux.
def create-app-linux [name: string runner: string] {
    let title = capitalize $name
    let icon_url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/marimo.svg"
    let dest = $"($nu.home-dir)/.local/app/($name)"
    let manifest = $"($nu.home-dir)/.local/share/applications/($name).desktop"

    mkdir $dest ($manifest | path dirname)
    http get $icon_url | save --force $"($dest)/icon.svg"
    create-entry $runner $title $dest

    $"
[Desktop Entry]
Exec=($dest)/main.sh
Icon=($dest)/icon.svg
Name=($title)
StartupWMClass=python3
Terminal=false
Type=Application
"
    | str trim --left
    | save --force $manifest
    update-desktop-database ($manifest | path dirname)

    log info $"Created application ($title) at ($dest)."
}

# Initialize application on macOS.
def create-app-macos [name: string runner: string] {
    let title = capitalize $name
    let identifier = $"com.scruffaluff.marimo-($name | str replace '_' '-')"
    let icon_url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/marimo.svg"
    let bundle = $"($nu.home-dir)/Applications/($title).app/Contents"
    let dest = $"($bundle)/MacOS"

    mkdir $dest $"($bundle)/Resources"
    let temp = mktemp --tmpdir --suffix ".svg"
    http get $icon_url | save --force $temp
    qlmanage -t -o ($temp | path dirname) -s 512 $temp
    sips --setProperty format icns --out $"($bundle)/Resources/icon.icns" $"($temp).png"
    rm --force $temp
    create-entry $runner $title $dest

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
    | str trim --left
    | save --force $"($bundle)/Info.plist"
    log info $"Created application ($title) at ($bundle)."
}

# Initialize application on Windows.
def create-app-windows [name: string runner: string] {
    let title = capitalize $name
    let icon_url = "https://molab.marimo.io/marimo_logo_green.svg"
    let dest = $"($env.LocalAppData)\\Programs\\App\\($name)"
    let menu_dir = $"($env.AppData)\\Microsoft\\Windows\\Start Menu\\Programs\\App"

    mkdir $dest
    let temp = mktemp --tmpdir --suffix ".svg"
    http get $icon_url | save --force $temp
    powershell -command $"
Add-Type -AssemblyName System.Drawing
$Bitmap = [System.Drawing.Bitmap]::FromFile\('($temp)'\)
$Icon = [System.Drawing.Icon]::FromHandle\($Bitmap.GetHicon\(\)\)
$Icon.Save\(\(New-Object System.IO.FileStream\('($dest + '\icon.ico')', [System.IO.FileMode]::Create\)\)\)
$Icon.Dispose\(\)
$Bitmap.Dispose\(\)
"
    rm --force $temp
    create-entry $runner $title $dest

    # Create Start Menu shortcut via PowerShell based on guide at
    # https://learn.microsoft.com/en-us/troubleshoot/windows-client/admin-development/create-desktop-shortcut-with-wsh.
    powershell -command $"
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut('($menu_dir)/($title).lnk')
$Shortcut.TargetPath = '($runner)'
$Shortcut.Arguments = '--no-config --quiet run --script \"($dest)\\main.py\"'
$Shortcut.IconLocation = '($dest)/icon.ico'
$Shortcut.WindowStyle = 7
$Shortcut.Save()
"

    log info $"Created application ($title) at ($dest)."
}

# Create application entrypoint script.
def create-entry [runner: path title: string folder: string] {
    let command = $"($runner | path basename) --no-config --quiet run --script"
    let notebook = r#'
# /// script
# dependencies = [
#   "matplotlib~=3.11",
#   "numpy~=2.5",
#   "polars~=2.0",
#   "scipy~=1.18",
#   "soundfile~=0.14.0",
# ]
# requires-python = ">=3.12.0,<4.0.0"
# ///

import marimo

app = marimo.App(width="medium")

with app.setup:
    import marimo as mo
'#
    | str trim --left

    let server = r#'
#!/usr/bin/env -S uv --no-config --quiet run --script
#
# /// script
# dependencies = [
#   "cryptography~=50.0",
#   "marimo~=0.25.2",
#   "pywebview~=6.2; sys_platform != 'linux'",
#   "pywebview[qt]~=6.2; sys_platform == 'linux'",
# ]
# requires-python = ">=3.12.0,<4.0.0"
# ///

import socket
import sys
import time
from pathlib import Path
from subprocess import Popen
from urllib import request

import webview


def find_port() -> int:
    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.bind(('', 0))
    _, port = tcp.getsockname()
    tcp.close()
    return port


def main() -> None:
    gui = "qt" if sys.platform == "linux" else None
    notebook = Path(__file__).parent / "notebook.py"
    port = find_port()
    url = f"http://localhost:{port}"

    server = Popen(
        [
            sys.executable,
            "-m",
            "marimo",
            "run",
            "--headless",
            "--sandbox",
            "--port",
            str(port),
            str(notebook),
        ],
    )

    wait_url(url)
    webview.create_window("'# + $title + r#'", url=url)
    webview.start(gui=gui)
    server.terminate()


def wait_url(url, timeout=10) -> None:
    start = time.time()
    while time.time() - start < timeout:
        try:
            request.urlopen(url, timeout=1)
            return
        except (ConnectionRefusedError, OSError):
            time.sleep(0.2)
    raise TimeoutError(f"Server did not respond at {url}")


if __name__ == "__main__":
    main()
'#
    | str trim --left

    if $nu.os-info.name == "windows" {
        let entry = $"($folder)/main.cmd"
        $"@echo off\n($command) \"%~dnp0.py\" %*\n" | save --force $entry
    } else {
        let entry = $"($folder)/main.sh"
        $"
#!/usr/bin/env sh
set -eu

# Add interpreter to system path.
export PATH=\"($runner | path dirname):${PATH}\"
# Resolve symlinks to find script folder.
folder=\"$\(dirname \"$\(realpath \"${0}\"\)\"\)\"
# Use interpeter to avoid env shebang conflicts.
exec ($command) \"${folder}/main.py\" \"\$@\"
"
        | str trim --left
        | save --force $entry
        chmod 755 $entry
    }

    if not ($"($folder)/notebook.py" | path exists) {
        $notebook | save $"($folder)/notebook.py"
    }
    $server | save --force $"($folder)/main.py"
}

# Find application runner.
def find-runner [] {
    if (which uv | is-empty) {
        http get https://scruffaluff.github.io/picoware/install/uv.nu
        | nu --commands $in --preserve-env
    }
    which uv | get 0.path
}

# Manage Marimo desktop applications.
def main [
    --version (-v) # Print version information
    command?: string # Subcommand
] {
    if $version {
        print "Mari 0.0.1"
        return
    }
    ensure-subcmd --meta (metadata $command) $command
}

# Initialize a Marimo desktop application.
def "main create" [
    name: string # Application name.
] {
    let title = capitalize $name
    log info $"Installing application ($title)."
    let runner = find-runner

    match $nu.os-info.name {
        linux => { create-app-linux $name $runner }
        macos => { create-app-macos $name $runner }
        windows => { create-app-windows $name $runner }
        _ => {
			error make $"Operating system ($nu.os-info.name) is not supported."
		}
    }
}

# Launch notebook in Marimo editor.
def "main edit" [
    name: string # Application name.
] {
    let ext = $name | path parse | get extension
    let notebook = if $ext == "py" or ($name | path exists) {
        $name
    } else {
        $"(main path $name)/notebook.py"
    }
    (
        uv --no-config --quiet tool run marimo --yes edit --sandbox --watch
        $notebook
    )
}

# Install notebook as desktop application.
def "main install" [
    --name (-n): string # Application name override.
    notebook: string # Notebook file.
] {
    let name = $name | default { $notebook | path parse | get stem }
    main create $name
    cp $notebook $"(main path $name)/notebook.py"
}

# Get path to application folder.
def "main path" [
    name: string # Application name.
] {
    let title = capitalize $name
    match $nu.os-info.name {
        linux => $"($nu.home-dir)/.local/app/($name)"
        macos => $"($nu.home-dir)/Applications/($title).app/Contents/MacOS"
        windows => $"($env.LocalAppData)/Programs/App/($name)"
        _ => {
			error make $"Operating system ($nu.os-info.name) is not supported."
		}
    }
}

# Launch desktop application.
def "main run" [
    name: string # Application name.
] {
    let server = $"(main path $name)/main.py"
    uv --no-config --quiet run --script $server
}
