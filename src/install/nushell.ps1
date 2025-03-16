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
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install Nushell
  -h, --help                Print help information
  -u, --user                Install Nushell for current user
  -v, --version <VERSION>   Version of Nushell to install
'@
}

# Print error message and exit script with usage error code.
Function ErrorUsage($Message) {
    Write-Output "error: $Message"
    Write-Output "Run 'install-nushell --help' for usage"
    Exit 2
}

# Find or download Jq JSON parser.
Function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    If ($JqBin) {
        Write-Output $JqBin
    }
    Else {
        $TempFile = [System.IO.Path]::GetTempFileName() -Replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe
        Write-Output $TempFile
    }
}

# Find latest version of Nushell
Function FindVersion($Version) {
    $Uri = 'https://api.github.com/repos/nushell/nushell/releases/latest'
    $Response = Invoke-WebRequest -UseBasicParsing -Uri "$Uri"

    $JqBin = FindJq
    Write-Output "$Response" | & $JqBin --exit-status --raw-output '.tag_name'
}

# Download and install Nushell.
Function InstallNushell($Target, $Version, $DestDir) {
    If ($Target -Eq 'Machine') {
        If (-Not $DestDir) {
            $DestDir = 'C:\Program Files\Nushell'
        }
        $Registry = 'HKLM:\Software\Classes'
    }
    Else {
        If (-Not $DestDir) {
            $DestDir = "$Env:LocalAppData\Nushell"
        }
        $Registry = 'HKCU:\Software\Classes'
    }

    Log "Installing Nushell to '$DestDir/nu.exe'."
    New-Item -Force -ItemType Directory -Path $DestDir | Out-Null
    $TmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $TmpDir | Out-Null
    New-Item -ItemType Directory -Path $TmpDir | Out-Null

    $Stem = "nu-$Version-x86_64-pc-windows-msvc"
    Invoke-WebRequest -UseBasicParsing -OutFile "$TmpDir/$Stem.zip" -Uri `
        "https://github.com/nushell/nushell/releases/download/$Version/$Stem.zip" `

    Expand-Archive -DestinationPath "$TmpDir/$Stem" -Path "$TmpDir/$Stem.zip"
    Copy-Item -Destination $DestDir -Path "$TmpDir/$Stem/*.exe"

    $Path = [Environment]::GetEnvironmentVariable('Path', "$Target")
    If (-Not ($Path -Like "*$DestDir*")) {
        $PrependedPath = "$DestDir;$Path"
        [System.Environment]::SetEnvironmentVariable(
            'Path', "$PrependedPath", "$Target"
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

    $PathExt = [Environment]::GetEnvironmentVariable('PATHEXT', "$Target")
    # User PATHEXT does not extend machine PATHEXT. Thus user PATHEXT must be
    # changed to machine PATHEXT + ';.NU' if prevously empty.
    If ((-Not $PathExt) -And ($Target -Eq 'User')) {
        $PathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Machine')
    }
    If (-Not ($PathExt -Like "*.NU*")) {
        $AppendedPath = "$PathExt;.NU".TrimStart(';')
        [System.Environment]::SetEnvironmentVariable(
            'PATHEXT', "$AppendedPath", "$Target"
        )
        $Env:PATHEXT = $AppendedPath
        Log "Registered '.nu' files as executables."
    }

    Log "Installed Nushell $(nu --version)."
}

# Print log message to stdout if logging is enabled.
Function Log($Message) {
    If (!"$Env:SCRIPTS_NOLOG") {
        Write-Output "$Message"
    }
}

# Script entrypoint.
Function Main() {
    $ArgIdx = 0
    $DestDir = ''
    $Target = 'Machine'
    $Version = ''

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-d', '--dest' } {
                $DestDir = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Exit 0
            }
            { $_ -In '-h', '--help' } {
                Usage
                Exit 0
            }
            '--user' {
                $Target = 'User'
                $ArgIdx += 1
                Break
            }
            { $_ -In '-v', '--version' } {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            Default {
                ErrorUsage "No such option '$($Args[0][$ArgIdx])'"
            }

        }
    }

    # Find latest Nushell version if not provided.
    If (-Not $Version) {
        $Version = FindVersion
    }
    InstallNushell $Target $Version $DestDir
}

# Only run Main if invoked as script. Otherwise import functions as library.
If ($MyInvocation.InvocationName -NE '.') {
    Main $Args
}
