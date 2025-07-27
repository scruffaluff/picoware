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
function Usage() {
    Write-Output @'
Installs Tmate and creates a remote session.

Usage: tmate-session [OPTIONS]

Options:
  -h, --help      Print help information
  -v, --version   Print version information
'@
}

function InstallTmate($URL) {
    if (-not (Get-Command -ErrorAction SilentlyContinue choco)) {
        Invoke-WebRequest -UseBasicParsing -Uri `
            'https://chocolatey.org/install.ps1' | Invoke-Expression
    }

    if (-not (Get-Command -ErrorAction SilentlyContinue pacman)) {
        choco install --yes msys2
    }

    pacman --noconfirm --sync tmate
}

# Print SetupTmate version string.
function Version() {
    Write-Output 'SetupTmate 0.4.1'
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-h', '--help' } {
                Usage
                return
            }
            { $_ -in '-v', '--version' } {
                Version
                return
            }
            default {
                $ArgIdx += 1
            }
        }
    }

    $Env:Path = 'C:\tools\msys64\usr\bin;' + "$Env:Path"
    if (-not (Get-Command -ErrorAction SilentlyContinue tmate)) {
        InstallTmate
    }

    # Set Msys2 environment variables.
    $Env:CHERE_INVOKING = 'true'
    $Env:MSYS2_PATH_TYPE = 'inherit'
    $Env:MSYSTEM = 'MINGW64'
    if ($Env:SystemRoot) {
        $CloseFile = "$Env:SystemRoot\Temp\close_tmate"
    }
    else {
        $CloseFile = 'C:\Windows\Temp\close_tmate'
    }

    # Launch new Tmate session with custom socket.
    #
    # Flags:
    #   -S: Set Tmate socket path.
    tmate -S /tmp/tmate.sock new-session -d
    tmate -S /tmp/tmate.sock wait tmate-ready
    $SSHConnect = sh -l -c "tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}'"
    $WebConnect = sh -l -c "tmate -S /tmp/tmate.sock display -p '#{tmate_web}'"

    Write-Output 'Tmate session started.'
    Write-Output "Terminate the session by creating the file $CloseFile."
    while ($True) {
        Write-Output "SSH: $SSHConnect"
        Write-Output "Web shell: $WebConnect"

        # Check if script should exit.
        if (
            (-not (sh -l -c 'ls /tmp/tmate.sock 2> /dev/null')) -or
            (Test-Path $CloseFile)
        ) {
            break
        }

        Start-Sleep 5
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
