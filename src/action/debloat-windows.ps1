<#
.SYNOPSIS
    Remove Windows clutter with Raphire's Win11Debloat.
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
Remove Windows clutter with Raphire's Win11Debloat. For Win11Debloat flags,
visit https://github.com/Raphire/Win11Debloat/wiki/Command%E2%80%90line-Interface.

Usage: debloat-windows [OPTIONS] <ARGS>...

Options:
  -h, --help      Print help information
  -v, --version   Print version information
'@
}

# Print DebloatWindows version string.
function Version() {
    Write-Output 'DebloatWindows 0.0.1'
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

    & ([ScriptBlock]::Create((Invoke-RestMethod "https://debloat.raphi.re/"))) `
        -CLI `
        -DisableBraveBloat `
        -DisableDVR `
        -DisableDeliveryOptimization `
        -DisableDesktopSpotlight `
        -DisableEdgeAI `
        -DisableFindMyDevice `
        -DisableGameBarIntegration `
        -DisableLocationServices `
        -DisableNotepadAI `
        -DisablePaintAI `
        -DisableSearchHighlights `
        -DisableSearchHistory `
        -DisableSettings365Ads `
        -DisableStartPhoneLink `
        -DisableStartRecommended `
        -ExplorerToHome `
        -HideOnedrive `
        -HideSearchTb `
        -HideTaskview `
        -PreventUpdateAutoReboot `
        -RemoveCommApps `
        -RemoveDevApps `
        -RemoveGamingApps `
        -RemoveHPApps `
        -RunDefaults `
        -ShowHiddenFolders `
        -Silent `
        $Args
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
