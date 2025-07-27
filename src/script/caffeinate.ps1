<#
.SYNOPSIS
    Prevent system from sleeping during a program.
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
Prevent the system from sleeping during a command.

Usage: caffeinate [OPTIONS]

Options:
  -h, --help      Print help information
  -v, --version   Print version information
'@
}

# Print Caffeinate version string.
function Version() {
    Write-Output 'Caffeinate 0.2.0'
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0
    $CmdArgs = @()

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
                $CmdArgs += $Args[0][$ArgIdx]
                $ArgIdx += 1
            }
        }
    }

    caffeine
    try {
        if ($CmdArgs.Count -eq 0) {
            while ($True) {
                Start-Sleep -Seconds 86400
            }
        }
        else {
            & $CmdArgs
        }
    }
    finally {
        caffeine --appexit
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
