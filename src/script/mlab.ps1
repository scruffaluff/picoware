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
Function Usage() {
    Switch ($Args[0]) {
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
        Default {
            Throw "No such usage option '$($Args[0])'"
        }
    }
}

# Print error message and exit script with usage error code.
Function ErrorUsage($Message, $Subcommand) {
    Write-Output "error: $Message"
    If ($Subcommand) {
        Write-Output "Run 'mlab $Subcommand --help' for usage"
    }
    Else {
        Write-Output "Run 'mlab --help' for usage"
    }
    Exit 2
}

# Find Matlab executable on system.
Function FindMatlab() {
    $InstallPath = 'C:/Program Files/MATLAB'
    $Program = ''

    If ($Env:MLAB_PROGRAM) {
        $Program = $Env:MLAB_PROGRAM
    }
    ElseIf (Test-Path -Path $InstallPath -PathType Container) {
        $Folders = $(Get-ChildItem -Filter 'R*' -Path $InstallPath)
        ForEach ($Folder In $Folders) {
            $Program = "$InstallPath/$Folder/bin/matlab.exe"
            Break
        }
    }

    # Throw error if Matlab was not found.
    If ($Program) {
        Return $Program
    }
    Else {
        Throw 'Unable to find a Matlab installation'
    }
}

# Convert Matlab script into a module call.
Function GetModule($Path) {
    Switch ($Path) {
        { $_ -Like "*.m" } {
            Return [System.IO.Path]::GetFileNameWithoutExtension($Path)
        }
        Default {
            Return $Path
        }
    }
}

# Get parameters for subcommands.
Function GetParameters($Params, $Index) {
    If ($Params.Length -GT $Index) {
        Return $Params[$Index..($Params.Length - 1)]
    }
    Else {
        Return @()
    }
}

# Launch Jupyter Lab with the Matlab kernel.
Function Jupyter() {
    $ArgIdx = 0
    $LocalDir = "$Env:LOCALAPPDATA/mlab"

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-h', '--help' } {
                Usage 'run'
                Exit 0
            }
            Default {
                $ArgIdx += 1
            }
        }
    }

    $MatlabDir = "$(FindMatlab)"
    If (-Not (Test-Path -Path "$LocalDir/venv" -PathType Container)) {
        New-Item -Force -ItemType Directory -Path $LocalDir | Out-Null
        python3 -m venv "$LocalDir/venv"
        & "$LocalDir/venv/Scripts/pip.exe" install jupyter-matlab-proxy jupyterlab
    }

    & "$LocalDir/venv/Scripts/activate.ps1"
    $Env:Path = $MatlabDir + ";$Env:Path"
    jupyter lab $Args
}

# Subcommand to execute Matlab code.
Function Run() {
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

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-a', '--addpath' } {
                $PathCmd = "addpath('" + $Args[0][$ArgIdx + 1] + "'); "
                $ArgIdx += 2
                Break
            }
            { $_ -In '-b', '--batch' } {
                $Batch = $True
                $ArgIdx += 1
                Break
            }
            { $_ -In '-c', '--license' } {
                $BinaryArgs += '-c'
                $BinaryArgs += $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            { $_ -In '-d', '--debug' } {
                $Debug = $True
                $ArgIdx += 1
                Break
            }
            { $_ -In '-e', '--echo' } {
                $Print = $True
                $ArgIdx += 1
                Break
            }
            { $_ -In '-g', '--genpath' } {
                $PathCmd = "addpath(genpath('" + $Args[0][$ArgIdx + 1] + "')); "
                $ArgIdx += 2
                Break
            }
            { $_ -In '-h', '--help' } {
                Usage 'run'
                Exit 0
            }
            { $_ -In '-i', '--interactive' } {
                $Interactive = $True
                $ArgIdx += 1
                Break
            }
            { $_ -In '-l', '-logfile', '--logfile' } {
                $BinaryArgs += '-logfile'
                $BinaryArgs += $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            { $_ -In '-s', '-sd', '--sd' } {
                $BinaryArgs += '-sd'
                $BinaryArgs += $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            Default {
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
    If ($Script) {
        If ($Debug) {
            $Command = "dbstop if error; dbstop in $Module; $Module; exit"
        }
        ElseIf ($Interactive) {
            $Command = "$Module"
        }
        Else {
            $Command = "$Module"
            $Display = '-nodesktop'
            $Flag = '-batch'
        }
    }
    ElseIf ($Batch) {
        $Display = '-nodesktop'
        $Flag = '-batch'
    }
    ElseIf ($Debug) {
        $Command = 'dbstop if error;'
    }

    # Add parent path to Matlab if command is a script.
    If ($Script -And ($Module -NE $Script)) {
        $Folder = [System.IO.Path]::GetDirectoryName($Script)
        If ($Folder -NotLike "+*") {
            $Command = "addpath('$Folder'); $Command"
        }
    }

    $Command = "$PathCmd$Command"
    If ($Command) {
        $FlagArgs = '-nosplash', $Flag, $Command
    }
    Else {
        $FlagArgs = @('-nosplash')
    }

    $Program = "$(FindMatlab)"
    If ($Print -And ($BinaryArgs.Count -GT 0)) {
        Write-Output "& $Program $BinaryArgs $Display $FlagArgs"
    }
    ElseIf ($Print) {
        Write-Output "& $Program $Display $FlagArgs"
    }
    ElseIf ($BinaryArgs.Count -GT 0) {
        & $Program $BinaryArgs $Display $FlagArgs
    }
    Else {
        & $Program $Display $FlagArgs
    }
}

# Print Mlab version string.
Function Version() {
    Write-Output 'Mlab 0.0.5'
}

# Script entrypoint.
Function Main() {
    $ArgIdx = 0

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-h', '--help' } {
                Usage 'main'
                Exit 0
            }
            { $_ -In '-v', '--version' } {
                Version
                Exit 0
            }
            'jupyter' {
                $ArgIdx += 1
                Jupyter @(GetParameters $Args[0] $ArgIdx)
                Exit 0
            }
            'run' {
                $ArgIdx += 1
                Run @(GetParameters $Args[0] $ArgIdx)
                Exit 0
            }
            Default {
                ErrorUsage "No such subcommand or option '$($Args[0][0])'"
            }
        }
    }

    Usage 'main'
}

# Only run Main if invoked as script. Otherwise import functions as library.
If ($MyInvocation.InvocationName -NE '.') {
    Main $Args
}
