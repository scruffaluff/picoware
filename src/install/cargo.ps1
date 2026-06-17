<#
.SYNOPSIS
    Install Cargo for Windows systems.
#>

# If unable to execute due to policy rules, run
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser.

# Exit immediately if a PowerShell cmdlet encounters an error.
$ErrorActionPreference = 'Stop'
# Disable progress bar for PowerShell cmdlets.
$ProgressPreference = 'SilentlyContinue'
# Exit immediately when an native executable encounters an error.
$PSNativeCommandUseErrorActionPreference = $True

# Show CLI help information.
function Usage() {
    Write-Output @'
Installer script for Cargo.

Usage: install-cargo [OPTIONS]

Options:
  -d, --dest <PATH>         Directory to install Cargo
  -h, --help                Print help information
  -p, --preserve-env        Do not update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Rust to install
'@
}

# Download and install Cargo.
function InstallCargo($Version, $DestDir, $PreserveEnv) {
    $Arch = $Env:PROCESSOR_ARCHITECTURE -replace 'AMD64', 'x86_64' `
        -replace 'ARM64', 'aarch64'
    $BinDir = "$DestDir\bin"

    # Determine RUSTUP_HOME based on destination directory name.
    $DestName = [System.IO.Path]::GetFileName($DestDir)
    if ($DestName -like '.*') {
        $RustupHome = "$([System.IO.Path]::GetDirectoryName($DestDir))\.rustup"
    }
    else {
        $RustupHome = "$([System.IO.Path]::GetDirectoryName($DestDir))\rustup"
    }

    # Build rustup installer arguments.
    $ArgsList = @('-y', '--no-modify-path', '--profile', 'minimal')
    if ($Env:SCRIPTS_NOLOG) {
        $ArgsList += '--quiet'
    }
    if ($Version) {
        $ArgsList += '--default-toolchain', $Version
    }

    Log "Installing Cargo to '$DestDir\bin\cargo.exe'."
    $TmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $TmpDir | Out-Null
    New-Item -ItemType Directory -Path $TmpDir | Out-Null

    Invoke-WebRequest -UseBasicParsing -OutFile "$TmpDir\rustup-init.exe" -Uri `
        "https://static.rust-lang.org/rustup/dist/$Arch-pc-windows-msvc/rustup-init.exe"

    $Env:CARGO_HOME = $DestDir
    $Env:RUSTUP_HOME = $RustupHome
    $Env:Path = "$BinDir;$Env:Path"
    & "$TmpDir\rustup-init.exe" $ArgsList

    if (-not $PreserveEnv) {
        $Path = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not ($Path -like "*$BinDir*")) {
            $PrependedPath = "$BinDir;$Path"
            [System.Environment]::SetEnvironmentVariable(
                'Path', "$PrependedPath", 'User'
            )
            Log "Added '$BinDir' to the system path."
            Log 'Source shell profile or restart shell after installation.'
        }
    }

    Log "Installed $(cargo --version)."
}

# Print message if logging is enabled.
function Log($Text) {
    if (!"$Env:SCRIPTS_NOLOG") {
        Write-Output $Text
    }
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0
    $DestDir = ''
    $PreserveEnv = $False
    $Version = ''

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-d', '--dest' } {
                $DestDir = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            { $_ -in '-h', '--help' } {
                Usage
                return
            }
            { $_ -in '-p', '--preserve-env' } {
                $PreserveEnv = $True
                $ArgIdx += 1
                break
            }
            { $_ -in '-q', '--quiet' } {
                $Env:SCRIPTS_NOLOG = 'true'
                $ArgIdx += 1
                break
            }
            { $_ -in '-v', '--version' } {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            default {
                Log "error: No such option '$($Args[0][$ArgIdx])'."
                Log "Run 'install-cargo --help' for usage."
                exit 2
            }

        }
    }

    # Create destination folder if it does not exist.
    if (-not $DestDir) {
        $DestDir = "$HOME\.cargo"
    }
    New-Item -Force -ItemType Directory -Path $DestDir | Out-Null
    $DestDir = [System.IO.Path]::GetFullPath($DestDir)
    InstallCargo $Version $DestDir $PreserveEnv
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
