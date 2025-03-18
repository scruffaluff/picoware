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
Function Usage() {
    Write-Output @'
Installer script for Nushell.

Usage: install-nushell [OPTIONS]

Options:
  -d, --dest <PATH>         Directory to install Nushell
  -g, --global              Install Nushell for all users
  -h, --help                Print help information
  -m, --modify-env          Update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Nushell to install
'@
}

# Find or download Jq JSON parser.
Function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    If ($JqBin) {
        Write-Output $JqBin
    }
    Else {
        $Arch = $Env:PROCESSOR_ARCHITECTURE.ToLower()
        $TempFile = [System.IO.Path]::GetTempFileName() -Replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            "https://github.com/jqlang/jq/releases/latest/download/jq-windows-$Arch.exe"
        Write-Output $TempFile
    }
}

# Find latest Nushell version.
Function FindLatest($Version) {
    $JqBin = FindJq
    $Response = Invoke-WebRequest -UseBasicParsing -Uri `
        https://formulae.brew.sh/api/formula/nushell.json
    Write-Output "$Response" | & $JqBin --exit-status --raw-output `
        '.versions.stable'
}

# Download and install Nushell.
Function InstallNushell($TargetEnv, $Version, $DestDir, $ModifyEnv) {
    $Arch = $Env:PROCESSOR_ARCHITECTURE -Replace 'AMD64', 'x86_64' `
        -Replace 'ARM64', 'aarch64'

    Log "Installing Nushell to '$DestDir\nu.exe'."
    $TmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $TmpDir | Out-Null
    New-Item -ItemType Directory -Path $TmpDir | Out-Null

    $Target = "nu-$Version-$Arch-pc-windows-msvc"
    Invoke-WebRequest -UseBasicParsing -OutFile "$TmpDir\$Target.zip" -Uri `
        "https://github.com/nushell/nushell/releases/download/$Version/$Target.zip"

    Expand-Archive -DestinationPath "$TmpDir\$Target" -Path "$TmpDir\$Target.zip"
    Copy-Item -Destination $DestDir -Path "$TmpDir\$Target\*.exe"

    If ($ModifyEnv) {
        $Path = [Environment]::GetEnvironmentVariable('Path', $TargetEnv)
        If (-Not ($Path -Like "*$DestDir*")) {
            $PrependedPath = "$DestDir;$Path"
            [System.Environment]::SetEnvironmentVariable(
                'Path', "$PrependedPath", $TargetEnv
            )
            Log "Added '$DestDir' to the system path."
            $Env:Path = $PrependedPath
        }

        If (-Not (Get-ItemProperty -ErrorAction SilentlyContinue -Name '(Default)' -Path "$Registry\.nu")) {
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
        If ((-Not $PathExt) -And ($TargetEnv -Eq 'User')) {
            $PathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Machine')
        }
        If (-Not ($PathExt -Like "*.NU*")) {
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

# Print message if logging is enabled.
Function Log($Text) {
    If (!"$Env:SCRIPTS_NOLOG") {
        Write-Output $Text
    }
}

# Script entrypoint.
Function Main() {
    $ArgIdx = 0
    $DestDir = ''
    $ModifyEnv = $False
    $Version = ''

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-d', '--dest' } {
                $DestDir = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            { $_ -In '-g', '--global' } {
                if (-Not $DestDir) {
                    $DestDir = 'C:\Program Files\Bin'
                }
                $ArgIdx += 1
                Break
            }
            { $_ -In '-h', '--help' } {
                Usage
                Exit 0
            }
            { $_ -In '-m', '--modify-env' } {
                $ModifyEnv = $True
                $ArgIdx += 1
                Break
            }
            { $_ -In '-q', '--quiet' } {
                $Env:SCRIPTS_NOLOG = 'true'
                $ArgIdx += 1
                Break
            }
            { $_ -In '-v', '--version' } {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            Default {
                Log "error: No such option '$($Args[0][$ArgIdx])'."
                Log "Run 'install-nushell --help' for usage."
                Exit 2
            }

        }
    }

    # Create destination folder if it does not exist for Resolve-Path.
    If (-Not $DestDir) {
        $DestDir = "$Env:LocalAppData\Programs\Bin"
    }
    New-Item -Force -ItemType Directory -Path $DestDir | Out-Null

    # Set environment target on whether destination is inside user home folder.
    $DestDir = $(Resolve-Path -Path $DestDir).Path
    $HomeDir = $(Resolve-Path -Path $HOME).Path
    If ($DestDir.StartsWith($HomeDir)) {
        $TargetEnv = 'User'
    }
    Else {
        $TargetEnv = 'Machine'
    }

    # Find latest Nushell version if not provided.
    If (-Not $Version) {
        $Version = FindLatest
    }
    InstallNushell $TargetEnv $Version $DestDir $ModifyEnv
}

# Only run Main if invoked as script. Otherwise import functions as library.
If ($MyInvocation.InvocationName -NE '.') {
    Main $Args
}
