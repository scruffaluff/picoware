<#
.SYNOPSIS
    Interactive Ripgrep searcher based on logic from
    https://github.com/junegunn/fzf/blob/master/ADVANCED.md#using-fzf-as-interactive-ripgrep-launcher.
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
Interactive Ripgrep searcher.

Usage: rgi [OPTIONS] [RG_ARGS]...

Options:
      --debug     Show shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information

Ripgrep Options:
'@
    If (Get-Command -ErrorAction SilentlyContinue rg) {
        rg --help
    }
}

# Print Rgi version string.
Function Version() {
    Write-Output 'Rgi 0.0.2'
}

# Script entrypoint.
Function Main() {
    $ArgIdx = 0
    $Editor = 'vim'
    $RgCmd = 'rg --column --line-number --no-heading --smart-case --color always'

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
                $Argument = $Args[0][$ArgIdx]
                $RgCmd = "$RgCmd '$Argument'"
                $ArgIdx += 1
            }
        }
    }

    If ($Env:EDITOR) {
        $Editor = $Env:Editor
    }
    fzf --ansi `
        --bind "enter:become(& '$Editor {1}:{2}')" `
        --bind "start:reload:$RgCmd" `
        --delimiter ':' `
        --preview 'bat --color always --highlight-line {2} {1}' `
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3'
}

# Only run Main if invoked as script. Otherwise import functions as library.
If ($MyInvocation.InvocationName -NE '.') {
    Main $Args
}
