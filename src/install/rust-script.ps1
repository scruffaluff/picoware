<#
.SYNOPSIS
    Install Rust Script for Windows systems.
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
Installer script for Rust Script.

Usage: install-rust-script [OPTIONS]

Options:
  -d, --dest <PATH>         Directory to install Rust Script
  -g, --global              Install Rust Script for all users
  -h, --help                Print help information
  -p, --preserve-env        Do not update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Rust Script to install
'@
}

# Find or download Jq JSON parser.
function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    if ($JqBin) {
        $JqBin
    }
    else {
        $Arch = $Env:PROCESSOR_ARCHITECTURE.ToLower()
        $TempFile = [System.IO.Path]::GetTempFileName() -replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            "https://github.com/jqlang/jq/releases/latest/download/jq-windows-$Arch.exe"
        $TempFile
    }
}

# Find latest Rust Script version.
function FindLatest($Version) {
    $JqBin = FindJq
    $Response = Invoke-WebRequest -UseBasicParsing -Uri `
        https://formulae.brew.sh/api/formula/rust-script.json
    "$Response" | & $JqBin --exit-status --raw-output '.versions.stable'
}

# Check if script is run from an admin console.
function IsAdministrator {
    ([Security.Principal.WindowsPrincipal]`
        [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Download and install Rust Script.
function InstallRustScript($TargetEnv, $Version, $DestDir, $PreserveEnv) {
    $Arch = $Env:PROCESSOR_ARCHITECTURE -replace 'AMD64', 'x86_64' `
        -replace 'ARM64', 'aarch64'

    Log "Installing Rust Script to '$DestDir\rust-script.exe'."
    $TmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $TmpDir | Out-Null
    New-Item -ItemType Directory -Path $TmpDir | Out-Null

    $Target = "rust-script-$Arch-pc-windows-msvc"
    Invoke-WebRequest -UseBasicParsing -OutFile "$TmpDir\$Target.zip" -Uri `
        "https://github.com/fornwall/rust-script/releases/download/$Version/$Target.zip"

    Expand-Archive -DestinationPath $TmpDir -Path "$TmpDir\$Target.zip"
    Copy-Item -Destination $DestDir -Path "$TmpDir\rust-script.exe"

    if (-not $PreserveEnv) {
        $Path = [Environment]::GetEnvironmentVariable('Path', $TargetEnv)
        if (-not ($Path -like "*$DestDir*")) {
            $PrependedPath = "$DestDir;$Path"
            [System.Environment]::SetEnvironmentVariable(
                'Path', "$PrependedPath", $TargetEnv
            )
            Log "Added '$DestDir' to the system path."
            Log 'Source shell profile or restart shell after installation.'
        }

        if ($TargetEnv -eq 'Machine') {
            $Registry = 'HKLM:\Software\Classes'
        }
        else {
            $Registry = 'HKCU:\Software\Classes'
        }
        if (-not (Get-ItemProperty -ErrorAction SilentlyContinue -Name '(Default)' -Path "$Registry\.rs")) {
            New-Item -Force -Path "$Registry\.rs" | Out-Null
            Set-ItemProperty -Name '(Default)' -Path "$Registry\.rs" -Type String `
                -Value 'rsfile'

            $Command = '"' + "$DestDir\rust-script.exe" + '" "%1" %*'
            New-Item -Force -Path "$Registry\rsfile\shell\open\command" | Out-Null
            Set-ItemProperty -Name '(Default)' -Path "$Registry\rsfile\shell\open\command" `
                -Type String -Value $Command
            Log "Registered Rust Script to execute '.rs' files."
        }

        $PathExt = [Environment]::GetEnvironmentVariable('PATHEXT', $TargetEnv)
        # User PATHEXT does not extend machine PATHEXT. Thus user PATHEXT must be
        # changed to machine PATHEXT + ';.NU' if prevously empty.
        if ((-not $PathExt) -and ($TargetEnv -eq 'User')) {
            $PathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Machine')
        }
        if (-not ($PathExt -like "*.RS*")) {
            $AppendedPath = "$PathExt;.RS".TrimStart(';')
            [System.Environment]::SetEnvironmentVariable(
                'PATHEXT', $AppendedPath, $TargetEnv
            )
            $Env:PATHEXT = $AppendedPath
            Log "Registered '.rs' files as executables."
        }
    }

    $Env:Path = "$DestDir;$Env:Path"
    Log "Installed $(rust-script --version)."
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
            { $_ -in '-g', '--global' } {
                if (-not $DestDir) {
                    $DestDir = 'C:\Program Files\Bin'
                }
                $ArgIdx += 1
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
                Log "Run 'install-rust-script --help' for usage."
                exit 2
            }

        }
    }

    # Create destination folder if it does not exist for Resolve-Path.
    if (-not $DestDir) {
        $DestDir = "$Env:LocalAppData\Programs\Bin"
    }
    New-Item -Force -ItemType Directory -Path $DestDir | Out-Null

    # Set environment target on whether destination is inside user home folder.
    $DestDir = [System.IO.Path]::GetFullPath($DestDir)
    $HomeDir = [System.IO.Path]::GetFullPath($HOME)
    if ($DestDir.StartsWith($HomeDir)) {
        $TargetEnv = 'User'
    }
    else {
        $TargetEnv = 'Machine'
    }
    if (($TargetEnv -eq 'Machine') -and (-not (IsAdministrator))) {
        Log @'
System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
'@
        exit 1
    }

    # Find latest Rust Script version if not provided.
    if (-not $Version) {
        $Version = FindLatest
    }
    InstallRustScript $TargetEnv $Version $DestDir $PreserveEnv
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
