<#
.SYNOPSIS
    SCP for one time remote connections.
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
SCP for one time remote connections.

Usage: tscp [OPTIONS] <ARGS>...

Options:
  -h, --help      Print help information
  -v, --version   Print version information
'@
    if (Get-Command -ErrorAction SilentlyContinue scp) {
        Write-Output "`nSCP Options:"
        try {
            scp
        }
        catch [System.Management.Automation.NativeCommandExitException] {}
    }
}

# Print Tscp version string.
function Version() {
    Write-Output 'Tscp 0.3.0'
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0
    $CmdArgs = @()

    if ($Args[0].Count -eq 0) {
        Usage
        return
    }

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

    # Don't use PowerShell $Null for UserKnownHostsFile. It causes SSH to use
    # ~\.ssh\known_hosts as a backup.
    scp `
        -o IdentitiesOnly=yes `
        -o LogLevel=ERROR `
        -o PreferredAuthentications='publickey,password' `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        $CmdArgs
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
