<#
.SYNOPSIS
    Installs scripts for Windows systems.
#>

# If unable to execute due to policy rules, run
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser.

# Exit immediately if a PowerShell cmdlet encounters an error.
$ErrorActionPreference = 'Stop'
# Disable progress bar for PowerShell cmdlets.
$ProgressPreference = 'SilentlyContinue'
# Exit immediately when an native executable encounters an error.
$PSNativeCommandUseErrorActionPreference = $True

# Show CLI help information.
Function Usage() {
    Write-Output @'
Installer script for Scripts.

Usage: install [OPTIONS] [SCRIPTS]...

Options:
  -d, --dest <PATH>         Directory to install scripts
  -h, --help                Print help information
  -l, --list                List all available scripts
  -u, --user                Install scripts for current user
  -v, --version <VERSION>   Version of scripts to install
'@
}

# Print error message and exit script with usage error code.
Function ErrorUsage($Message) {
    Write-Output "error: $Message"
    Write-Output "Run 'install --help' for usage"
    Exit 2
}

# Find or download Jq JSON parser.
Function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    If ($JqBin) {
        Write-Output $JqBin
    }
    Else {
        $TempFile = [System.IO.Path]::GetTempFileName() -Replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe
        Write-Output $TempFile
    }
}

# Find all scripts inside GitHub repository.
Function FindScripts($Version) {
    $Filter = '.tree[] | select(.type == \"blob\") | .path | select(startswith(\"src/script/\")) | select(endswith(\".nu\") or endswith(\".ps1\")) | ltrimstr(\"src/script/\")'
    $Uri = "https://api.github.com/repos/scruffaluff/scripts/git/trees/$Version`?recursive=true"
    $Response = Invoke-WebRequest -UseBasicParsing -Uri "$Uri"

    $JqBin = FindJq
    Write-Output "$Response" | & $JqBin --exit-status --raw-output "$Filter"
}

# Install script and update path.
Function InstallScript($Target, $SrcPrefix, $DestDir, $Script) {
    $Name = [IO.Path]::GetFileNameWithoutExtension($Script)
    New-Item -Force -ItemType Directory -Path $DestDir | Out-Null

    $URL = "https://raw.githubusercontent.com/scruffaluff/scripts/$Version"
    If (
        $ScriptName.EndsWith('.nu') -And
        (-Not (Get-Command -ErrorAction SilentlyContinue nu))
    ) {
        If ($Target -Eq 'Machine') {
            Invoke-WebRequest -UseBasicParsing -Uri `
                "$URL/src/install/nushell.ps1" | Invoke-Expression
        }
        Else {
            powershell {
                Invoke-Expression `
                    "& { $(Invoke-WebRequest -UseBasicParsing -Uri $URL/src/install/nushell.ps1) } --user"
            }
        }
    }

    Log "Installing script $Name to '$DestDir/$Name'."
    Invoke-WebRequest -UseBasicParsing -OutFile "$DestDir/$Script" `
        -Uri "$URL/src/script/$Script"

    # Add destination folder to system path.
    $Path = [Environment]::GetEnvironmentVariable('Path', "$Target")
    If (-Not ($Path -Like "*$DestDir*")) {
        $PrependedPath = "$DestDir;$Path"
        [System.Environment]::SetEnvironmentVariable(
            'Path', "$PrependedPath", "$Target"
        )
        Log "Added '$DestDir' to the system path."
        Log 'Restart the shell after installation.'
        $Env:Path = $PrependedPath
    }
    Log "Installed $(& $Name --version)."
}

# Print log message to stdout if logging is enabled.
Function Log($Message) {
    If (!"$Env:SCRIPTS_NOLOG") {
        Write-Output "$Message"
    }
}

# Script entrypoint.
Function Main() {
    $ArgIdx = 0
    $DestDir = ''
    $List = $False
    $Names = @()
    $Target = 'Machine'
    $Version = 'main'

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-d', '--dest' } {
                $DestDir = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Exit 0
            }
            { $_ -In '-h', '--help' } {
                Usage
                Exit 0
            }
            { $_ -In '-l', '--list' } {
                $List = $True
                $ArgIdx += 1
                Break
            }
            { $_ -In '-v', '--version' } {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            '--user' {
                if (-Not $DestDir) {
                    $DestDir = "$Env:LocalAppData\Programs\Bin"
                }
                $Target = 'User'
                $ArgIdx += 1
                Break
            }
            Default {
                $Names += $Args[0][$ArgIdx]
                $ArgIdx += 1
            }
        }
    }

    $Scripts = FindScripts "$Version"
    If (-Not $DestDir) {
        $DestDir = 'C:\Program Files\Bin'
    }

    If ($List) {
        ForEach ($Script in $Scripts) {
            Write-Output "$([IO.Path]::GetFileNameWithoutExtension($Script))"
        }
    }
    ElseIf ($Names) {
        ForEach ($Name in $Names) {
            $MatchFound = $False
            ForEach ($Script in $Scripts) {
                $ScriptName = [IO.Path]::GetFileNameWithoutExtension($Script)
                If ($ScriptName -Eq $Name) {
                    $MatchFound = $True
                    InstallScript $Target $Version $DestDir $Script
                }
            }

            If (-Not $MatchFound) {
                Throw "Error: No script name match found for '$Name'"
            }
        }
    }
    Else {
        ErrorUsage "Script argument required"
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
If ($MyInvocation.InvocationName -NE '.') {
    Main $Args
}
