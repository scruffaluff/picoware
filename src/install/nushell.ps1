<#
.SYNOPSIS
    Install Nushell for Windows systems.
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
Installer script for Nushell.

Usage: install-nushell [OPTIONS]

Options:
  -d, --dest <PATH>         Directory to install Nushell
  -g, --global              Install Nushell for all users
  -h, --help                Print help information
  -p, --preserve-env        Do not update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Nushell to install
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

# Find latest Nushell version.
function FindLatest($Version) {
    $JqBin = FindJq
    $Response = Invoke-WebRequest -UseBasicParsing -Uri `
        https://formulae.brew.sh/api/formula/nushell.json
    Write-Output "$Response" | & $JqBin --exit-status --raw-output `
        '.versions.stable'
}

# Download and install Nushell.
function InstallNushell($TargetEnv, $Version, $DestDir, $PreserveEnv) {
    $Arch = $Env:PROCESSOR_ARCHITECTURE -replace 'AMD64', 'x86_64' `
        -replace 'ARM64', 'aarch64'

    Log "Installing Nushell to '$DestDir\nu.exe'."
    $TmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $TmpDir | Out-Null
    New-Item -ItemType Directory -Path $TmpDir | Out-Null

    $Target = "nu-$Version-$Arch-pc-windows-msvc"
    Invoke-WebRequest -UseBasicParsing -OutFile "$TmpDir\$Target.zip" -Uri `
        "https://github.com/nushell/nushell/releases/download/$Version/$Target.zip"

    Expand-Archive -DestinationPath "$TmpDir\$Target" -Path "$TmpDir\$Target.zip"
    Copy-Item -Destination $DestDir -Path "$TmpDir\$Target\*.exe"

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
        if (-not (Get-ItemProperty -ErrorAction SilentlyContinue -Name '(Default)' -Path "$Registry\.nu")) {
            New-Item -Force -Path "$Registry\.nu" | Out-Null
            Set-ItemProperty -Name '(Default)' -Path "$Registry\.nu" -Type String `
                -Value 'nufile'

            $Command = '"' + "$DestDir\nu.exe" + '" "%1" %*'
            New-Item -Force -Path "$Registry\nufile\shell\open\command" | Out-Null
            Set-ItemProperty -Name '(Default)' -Path "$Registry\nufile\shell\open\command" `
                -Type String -Value $Command
            Log "Registered Nushell to execute '.nu' files."
        }

        $PathExt = [Environment]::GetEnvironmentVariable('PATHEXT', $TargetEnv)
        # User PATHEXT does not extend machine PATHEXT. Thus user PATHEXT must be
        # changed to machine PATHEXT + ';.NU' if prevously empty.
        if ((-not $PathExt) -and ($TargetEnv -eq 'User')) {
            $PathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Machine')
        }
        if (-not ($PathExt -like "*.NU*")) {
            $AppendedPath = "$PathExt;.NU".TrimStart(';')
            [System.Environment]::SetEnvironmentVariable(
                'PATHEXT', $AppendedPath, $TargetEnv
            )
            $Env:PATHEXT = $AppendedPath
            Log "Registered '.nu' files as executables."
        }
    }

    $Env:Path = "$DestDir;$Env:Path"
    Log "Installed Nushell $(nu --version)."
}

# Check if script is run from an admin console.
function IsAdministrator {
    return ([Security.Principal.WindowsPrincipal]`
            [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
                Log "Run 'install-nushell --help' for usage."
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

    # Find latest Nushell version if not provided.
    if (-not $Version) {
        $Version = FindLatest
    }
    InstallNushell $TargetEnv $Version $DestDir $PreserveEnv
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
