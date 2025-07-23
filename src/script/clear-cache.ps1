<#
.SYNOPSIS
    Frees up disk space by clearing caches of package managers.
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
Frees up disk space by clearing caches of package managers.

Usage: clear-cache [OPTIONS]

Options:
  -h, --help      Print help information
  -v, --version   Print version information
'@
}

# Print ClearCache version string.
function Version() {
    Write-Output 'ClearCache 0.3.0'
}

# Script entry point.
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

    if (Get-Command -ErrorAction SilentlyContinue scoop) {
        scoop cache rm --all
    }

    if (Get-Command -ErrorAction SilentlyContinue cargo-cache) {
        cargo-cache --autoclean
    }

    # Check if Docker client is install and Docker daemon is up and running.
    if (Get-Command -ErrorAction SilentlyContinue docker) {
        docker ps 2>&1 | Out-Null
        if (-not $LastExitCode) {
            docker system prune --force --volumes
        }
    }

    if (Get-Command -ErrorAction SilentlyContinue npm) {
        npm cache clean --force --loglevel error
    }

    if (Get-Command -ErrorAction SilentlyContinue pip) {
        pip cache purge
    }

    if (
        (Get-Command -ErrorAction SilentlyContinue playwright) -and
        (Test-Path -PathType Container "$Env:LocalAppData\ms-playwright\.links")
    ) {
        playwright uninstall --all
    }

    if (Get-Command -ErrorAction SilentlyContinue poetry) {
        foreach ($Cache in $(poetry cache list)) {
            poetry cache clear --all --no-interaction "$Cache"
        }
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
