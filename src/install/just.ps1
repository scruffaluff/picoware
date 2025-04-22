<#
.SYNOPSIS
    Install Just for Windows systems.
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
Installer script for Just.

Usage: install-just [OPTIONS]

Options:
  -d, --dest <PATH>         Directory to install Just
  -g, --global              Install Just for all users
  -h, --help                Print help information
  -p, --preserve-env        Do not update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Just to install
'@
}

# Find or download Jq JSON parser.
function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    if ($JqBin) {
        Write-Output $JqBin
    }
    else {
        $Arch = $Env:PROCESSOR_ARCHITECTURE.ToLower()
        $TempFile = [System.IO.Path]::GetTempFileName() -replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            "https://github.com/jqlang/jq/releases/latest/download/jq-windows-$Arch.exe"
        Write-Output $TempFile
    }
}

# Find latest Just version.
function FindLatest($Version) {
    $JqBin = FindJq
    $Response = Invoke-WebRequest -UseBasicParsing -Uri `
        https://formulae.brew.sh/api/formula/just.json
    Write-Output "$Response" | & $JqBin --exit-status --raw-output `
        '.versions.stable'
}

# Download and install Just.
function InstallJust($TargetEnv, $Version, $DestDir, $PreserveEnv) {
    $Arch = $Env:PROCESSOR_ARCHITECTURE -replace 'AMD64', 'x86_64' `
        -replace 'ARM64', 'aarch64'

    Log "Installing Just to '$DestDir\just.exe'."
    $TmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $TmpDir | Out-Null
    New-Item -ItemType Directory -Path $TmpDir | Out-Null

    $Target = "just-$Version-$Arch-pc-windows-msvc"
    Invoke-WebRequest -UseBasicParsing -OutFile "$TmpDir\$Target.zip" -Uri `
        "https://github.com/casey/just/releases/download/$Version/$Target.zip"

    Expand-Archive -DestinationPath "$TmpDir\$Target" -Path "$TmpDir\$Target.zip"
    Copy-Item -Destination $DestDir -Path "$TmpDir\$Target\just.exe"

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
    }

    $Env:Path = "$DestDir;$Env:Path"
    Log "Installed $(just --version)."
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
                exit 0
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
                Log "Run 'install-just --help' for usage."
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
    $DestDir = $(Resolve-Path -Path $DestDir).Path
    $HomeDir = $(Resolve-Path -Path $HOME).Path
    if ($DestDir.StartsWith($HomeDir)) {
        $TargetEnv = 'User'
    }
    else {
        $TargetEnv = 'Machine'
    }

    # Find latest Just version if not provided.
    if (-not $Version) {
        $Version = FindLatest
    }
    InstallJust $TargetEnv $Version $DestDir $PreserveEnv
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
