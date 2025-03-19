<#
.SYNOPSIS
    Invokes upgrade commands to all installed package managers.
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
Invokes upgrade commands to all installed package managers.

Usage: packup [OPTIONS]

Options:
  -h, --help      Print help information
  -v, --version   Print version information
'@
}

# Print Packup version string.
function Version() {
    Write-Output 'Packup 0.4.4'
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-h', '--help' } {
                Usage
                exit 0
            }
            { $_ -in '-v', '--version' } {
                Version
                exit 0
            }
            default {
                $ArgIdx += 1
            }
        }
    }

    if (Get-Command -ErrorAction SilentlyContinue choco) {
        choco upgrade --yes all
    }

    if (Get-Command -ErrorAction SilentlyContinue scoop) {
        scoop update
        scoop update --all
        scoop cleanup --all
    }

    if (Get-Command -ErrorAction SilentlyContinue cargo) {
        foreach ($Line in $(cargo install --list)) {
            if ("$Line" -like '*:') {
                cargo install $Line.Split()[0]
            }
        }
    }

    if (Get-Command -ErrorAction SilentlyContinue npm) {
        # The "npm install" command is run before "npm update" command to avoid
        # messages about newer versions of NPM being available.
        npm install --global npm@latest
        npm update --global --loglevel error
    }

    if (Get-Command -ErrorAction SilentlyContinue pipx) {
        pipx upgrade-all
    }

    if (Get-Command -ErrorAction SilentlyContinue tldr) {
        tldr --update
    }

    if (Get-Command -ErrorAction SilentlyContinue ya) {
        ya pack --upgrade
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
