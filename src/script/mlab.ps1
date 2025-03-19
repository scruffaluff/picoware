<#
.SYNOPSIS
    Wrapper script for running Matlab programs from the command line.
#>

# Exit immediately if a PowerShell cmdlet encounters an error.
$ErrorActionPreference = 'Stop'
# Disable progress bar for PowerShell cmdlets.
$ProgressPreference = 'SilentlyContinue'
# Exit immediately when an native executable encounters an error.
$PSNativeCommandUseErrorActionPreference = $True

# Show CLI help information.
function Usage() {
    switch ($Args[0]) {
        'main' {
            Write-Output @'
Wrapper script for running Matlab programs from the command line.

Usage: mlab [OPTIONS] [SUBCOMMAND]

Options:
  -h, --help        Print help information
  -v, --version     Print version information

Subcommands:
  jupyter   Launch Jupyter Lab with Matlab kernel
  run       Execute Matlab code
'@
        }
        'jupyter' {
            Write-Output @'
Launch Jupyter Lab with the Matlab kernel.

Usage: mlab jupyter [OPTIONS] [ARGS]...

Options:
  -h, --help        Print help information
'@
        }
        'run' {
            Write-Output @'
Execute Matlab code.

Usage: mlab run [OPTIONS] [SCRIPT] [ARGS]...

Options:
  -a, --addpath <PATH>        Add folder to Matlab path
  -b, --batch                 Use batch mode for session
  -c, --license <LOCATION>    Set location of Matlab license file
  -d, --debug                 Use Matlab debugger for session
  -e, --echo                  Print Matlab command and exit
  -h, --help                  Print help information
  -i, --interactive           Use interactive mode for session
  -l, --log <PATH>            Copy command window output to logfile
  -s, --sd <PATH>             Set the Matlab startup folder
'@
        }
        default {
            throw "No such usage option '$($Args[0])'"
        }
    }
}

# Print error message and exit script with usage error code.
function ErrorUsage($Message, $Subcommand) {
    Write-Output "error: $Message"
    if ($Subcommand) {
        Write-Output "Run 'mlab $Subcommand --help' for usage"
    }
    else {
        Write-Output "Run 'mlab --help' for usage"
    }
    exit 2
}

# Find Matlab executable on system.
function FindMatlab() {
    $InstallPath = 'C:/Program Files/MATLAB'
    $Program = ''

    if ($Env:MLAB_PROGRAM) {
        $Program = $Env:MLAB_PROGRAM
    }
    elseif (Test-Path -Path $InstallPath -PathType Container) {
        $Folders = $(Get-ChildItem -Filter 'R*' -Path $InstallPath)
        foreach ($Folder in $Folders) {
            $Program = "$InstallPath/$Folder/bin/matlab.exe"
            break
        }
    }

    # Throw error if Matlab was not found.
    if ($Program) {
        return $Program
    }
    else {
        throw 'Unable to find a Matlab installation'
    }
}

# Convert Matlab script into a module call.
function GetModule($Path) {
    switch ($Path) {
        { $_ -like "*.m" } {
            return [System.IO.Path]::GetFileNameWithoutExtension($Path)
        }
        default {
            return $Path
        }
    }
}

# Get parameters for subcommands.
function GetParameters($Params, $Index) {
    if ($Params.Length -gt $Index) {
        return $Params[$Index..($Params.Length - 1)]
    }
    else {
        return @()
    }
}

# Launch Jupyter Lab with the Matlab kernel.
function Jupyter() {
    $ArgIdx = 0
    $LocalDir = "$Env:LOCALAPPDATA/mlab"

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-h', '--help' } {
                Usage 'run'
                exit 0
            }
            default {
                $ArgIdx += 1
            }
        }
    }

    $MatlabDir = "$(FindMatlab)"
    if (-not (Test-Path -Path "$LocalDir/venv" -PathType Container)) {
        New-Item -Force -ItemType Directory -Path $LocalDir | Out-Null
        python3 -m venv "$LocalDir/venv"
        & "$LocalDir/venv/Scripts/pip.exe" install jupyter-matlab-proxy jupyterlab
    }

    & "$LocalDir/venv/Scripts/activate.ps1"
    $Env:Path = $MatlabDir + ";$Env:Path"
    jupyter lab $Args
}

# Subcommand to execute Matlab code.
function Run() {
    $ArgIdx = 0
    $Batch = $False
    $BinaryArgs = @()
    $Debug = $False
    $Display = '-nodisplay'
    $Flag = '-r'
    $Interactive = $False
    $PathCmd = ''
    $Print = $False
    $Script = ''

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-a', '--addpath' } {
                $PathCmd = "addpath('" + $Args[0][$ArgIdx + 1] + "'); "
                $ArgIdx += 2
                break
            }
            { $_ -in '-b', '--batch' } {
                $Batch = $True
                $ArgIdx += 1
                break
            }
            { $_ -in '-c', '--license' } {
                $BinaryArgs += '-c'
                $BinaryArgs += $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            { $_ -in '-d', '--debug' } {
                $Debug = $True
                $ArgIdx += 1
                break
            }
            { $_ -in '-e', '--echo' } {
                $Print = $True
                $ArgIdx += 1
                break
            }
            { $_ -in '-g', '--genpath' } {
                $PathCmd = "addpath(genpath('" + $Args[0][$ArgIdx + 1] + "')); "
                $ArgIdx += 2
                break
            }
            { $_ -in '-h', '--help' } {
                Usage 'run'
                exit 0
            }
            { $_ -in '-i', '--interactive' } {
                $Interactive = $True
                $ArgIdx += 1
                break
            }
            { $_ -in '-l', '-logfile', '--logfile' } {
                $BinaryArgs += '-logfile'
                $BinaryArgs += $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            { $_ -in '-s', '-sd', '--sd' } {
                $BinaryArgs += '-sd'
                $BinaryArgs += $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            default {
                $Script = $Args[0][$ArgIdx]
                $ArgIdx += 1
            }
        }
    }

    # Build Matlab command for script execution.
    #
    # Defaults to batch mode for script execution and interactive mode
    # otherwise.
    $Module = "$(GetModule $Script)"
    if ($Script) {
        if ($Debug) {
            $Command = "dbstop if error; dbstop in $Module; $Module; exit"
        }
        elseif ($Interactive) {
            $Command = "$Module"
        }
        else {
            $Command = "$Module"
            $Display = '-nodesktop'
            $Flag = '-batch'
        }
    }
    elseif ($Batch) {
        $Display = '-nodesktop'
        $Flag = '-batch'
    }
    elseif ($Debug) {
        $Command = 'dbstop if error;'
    }

    # Add parent path to Matlab if command is a script.
    if ($Script -and ($Module -ne $Script)) {
        $Folder = [System.IO.Path]::GetDirectoryName($Script)
        if ($Folder -notlike "+*") {
            $Command = "addpath('$Folder'); $Command"
        }
    }

    $Command = "$PathCmd$Command"
    if ($Command) {
        $FlagArgs = '-nosplash', $Flag, $Command
    }
    else {
        $FlagArgs = @('-nosplash')
    }

    $Program = "$(FindMatlab)"
    if ($Print -and ($BinaryArgs.Count -gt 0)) {
        Write-Output "& $Program $BinaryArgs $Display $FlagArgs"
    }
    elseif ($Print) {
        Write-Output "& $Program $Display $FlagArgs"
    }
    elseif ($BinaryArgs.Count -gt 0) {
        & $Program $BinaryArgs $Display $FlagArgs
    }
    else {
        & $Program $Display $FlagArgs
    }
}

# Print Mlab version string.
function Version() {
    Write-Output 'Mlab 0.0.5'
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-h', '--help' } {
                Usage 'main'
                exit 0
            }
            { $_ -in '-v', '--version' } {
                Version
                exit 0
            }
            'jupyter' {
                $ArgIdx += 1
                Jupyter @(GetParameters $Args[0] $ArgIdx)
                exit 0
            }
            'run' {
                $ArgIdx += 1
                Run @(GetParameters $Args[0] $ArgIdx)
                exit 0
            }
            default {
                ErrorUsage "No such subcommand or option '$($Args[0][0])'"
            }
        }
    }

    Usage 'main'
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
