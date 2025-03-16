<#
.SYNOPSIS
    Installs Tmate and creates a session suitable for CI. Based on logic from
    https://github.com/mxschmitt/action-tmate.
#>

# Exit immediately if a PowerShell cmdlet encounters an error.
$ErrorActionPreference = 'Stop'
# Disable progress bar for PowerShell cmdlets.
$ProgressPreference = 'SilentlyContinue'
# Exit immediately when an native executable encounters an error.
$PSNativeCommandUseErrorActionPreference = $True

# Show CLI help information.
Function Usage() {
    Write-Output @'
Installs Tmate and creates a remote session.

Users can close the session by creating the file /close-tmate.

Usage: run-tmate [OPTIONS]

Options:
  -h, --help      Print help information
  -v, --version   Print version information
'@
}

Function InstallTmate($URL) {
    If (-Not (Get-Command -ErrorAction SilentlyContinue choco)) {
        Invoke-WebRequest -UseBasicParsing -Uri `
            'https://chocolatey.org/install.ps1' | Invoke-Expression
    }

    If (-Not (Get-Command -ErrorAction SilentlyContinue pacman)) {
        choco install --yes msys2
    }

    pacman --noconfirm --sync tmate
}

# Print SetupTmate version string.
Function Version() {
    Write-Output 'SetupTmate 0.3.2'
}

# Script entrypoint.
Function Main() {
    $ArgIdx = 0

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-h', '--help' } {
                Usage
                Exit 0
            }
            { $_ -In '-v', '--version' } {
                Version
                Exit 0
            }
            Default {
                $ArgIdx += 1
            }
        }
    }

    $Env:Path = 'C:\tools\msys64\usr\bin;' + "$Env:Path"
    If (-Not (Get-Command -ErrorAction SilentlyContinue tmate)) {
        InstallTmate
    }

    # Set Msys2 environment variables.
    $Env:CHERE_INVOKING = 'true'
    $Env:MSYS2_PATH_TYPE = 'inherit'
    $Env:MSYSTEM = 'MINGW64'

    # Launch new Tmate session with custom socket.
    #
    # Flags:
    #   -S: Set Tmate socket path.
    tmate -S /tmp/tmate.sock new-session -d
    tmate -S /tmp/tmate.sock wait tmate-ready
    $SSHConnect = sh -l -c "tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}'"
    $WebConnect = sh -l -c "tmate -S /tmp/tmate.sock display -p '#{tmate_web}'"

    While ($True) {
        Write-Output "SSH: $SSHConnect"
        Write-Output "Web shell: $WebConnect"

        # Check if script should exit.
        If (
            (-Not (sh -l -c 'ls /tmp/tmate.sock 2> /dev/null')) -Or
            (Test-Path 'C:/tools/msys64/close-tmate') -Or
            (Test-Path './close-tmate')
        ) {
            Break
        }

        Start-Sleep 5
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
If ($MyInvocation.InvocationName -NE '.') {
    Main $Args
}
