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
function Usage() {
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
function ErrorUsage($Message) {
    Write-Output "error: $Message"
    Write-Output "Run 'install --help' for usage"
    exit 2
}

# Find or download Jq JSON parser.
function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    if ($JqBin) {
        Write-Output $JqBin
    }
    else {
        $TempFile = [System.IO.Path]::GetTempFileName() -replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe
        Write-Output $TempFile
    }
}

# Find all scripts inside GitHub repository.
function FindScripts($Version) {
    $Filter = '.tree[] | select(.type == \"blob\") | .path | select(startswith(\"src/script/\")) | select(endswith(\".nu\") or endswith(\".ps1\")) | ltrimstr(\"src/script/\")'
    $Uri = "https://api.github.com/repos/scruffaluff/scripts/git/trees/$Version`?recursive=true"
    $Response = Invoke-WebRequest -UseBasicParsing -Uri "$Uri"

    $JqBin = FindJq
    Write-Output "$Response" | & $JqBin --exit-status --raw-output "$Filter"
}

# Install script and update path.
function InstallScript($Target, $SrcPrefix, $DestDir, $Script) {
    $Name = [IO.Path]::GetFileNameWithoutExtension($Script)
    New-Item -Force -ItemType Directory -Path $DestDir | Out-Null

    $URL = "https://raw.githubusercontent.com/scruffaluff/scripts/$Version"
    if (
        $ScriptName.EndsWith('.nu') -and
        (-not (Get-Command -ErrorAction SilentlyContinue nu))
    ) {
        if ($Target -eq 'Machine') {
            Invoke-WebRequest -UseBasicParsing -Uri `
                "$URL/src/install/nushell.ps1" | Invoke-Expression
        }
        else {
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
    if (-not ($Path -like "*$DestDir*")) {
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
function Log($Message) {
    if (!"$Env:SCRIPTS_NOLOG") {
        Write-Output "$Message"
    }
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0
    $DestDir = ''
    $List = $False
    $Names = @()
    $Target = 'Machine'
    $Version = 'main'

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-d', '--dest' } {
                $DestDir = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            { $_ -in '-h', '--help' } {
                Usage
                exit 0
            }
            { $_ -in '-l', '--list' } {
                $List = $True
                $ArgIdx += 1
                break
            }
            { $_ -in '-v', '--version' } {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            '--user' {
                if (-not $DestDir) {
                    $DestDir = "$Env:LocalAppData\Programs\Bin"
                }
                $Target = 'User'
                $ArgIdx += 1
                break
            }
            default {
                $Names += $Args[0][$ArgIdx]
                $ArgIdx += 1
            }
        }
    }

    $Scripts = FindScripts "$Version"
    if (-not $DestDir) {
        $DestDir = 'C:\Program Files\Bin'
    }

    if ($List) {
        foreach ($Script in $Scripts) {
            Write-Output "$([IO.Path]::GetFileNameWithoutExtension($Script))"
        }
    }
    elseif ($Names) {
        foreach ($Name in $Names) {
            $MatchFound = $False
            foreach ($Script in $Scripts) {
                $ScriptName = [IO.Path]::GetFileNameWithoutExtension($Script)
                if ($ScriptName -eq $Name) {
                    $MatchFound = $True
                    InstallScript $Target $Version $DestDir $Script
                }
            }

            if (-not $MatchFound) {
                throw "Error: No script name match found for '$Name'"
            }
        }
    }
    else {
        ErrorUsage "Script argument required"
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
