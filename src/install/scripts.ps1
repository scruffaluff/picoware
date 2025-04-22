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

Usage: install-scripts [OPTIONS] [SCRIPTS]...

Options:
  -d, --dest <PATH>         Directory to install scripts
  -g, --global              Install scripts for all users
  -h, --help                Print help information
  -l, --list                List all available scripts
  -p, --preserve-env        Do not update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of scripts to install
'@
}

# Find or download Jq JSON parser.
function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    if ($JqBin) {
        Write-Output $JqBin
    }
    else {
        $Arch = $Env:PROCESSOR_ARCHITECTURE.ToLower()
        $TempFile = [System.IO.Path]::GetTempFileName() -replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            "https://github.com/jqlang/jq/releases/latest/download/jq-windows-$Arch.exe"
        Write-Output $TempFile
    }
}

# Find all scripts inside GitHub repository.
function FindScripts($Version) {
    $Filter = '.tree[] | select(.type == \"blob\") | .path | select(startswith(\"src/script/\")) | select(endswith(\".nu\") or endswith(\".ps1\")) | ltrimstr(\"src/script/\")'
    $JqBin = FindJq
    $Response = Invoke-WebRequest -UseBasicParsing -Uri `
        "https://api.github.com/repos/scruffaluff/scripts/git/trees/$Version`?recursive=true"
    Write-Output "$Response" | & $JqBin --exit-status --raw-output "$Filter"
}

# Install script and update path.
function InstallScript($TargetEnv, $Version, $DestDir, $Script, $PreserveEnv) {
    $Name = [IO.Path]::GetFileNameWithoutExtension($Script)
    $URL = "https://raw.githubusercontent.com/scruffaluff/scripts/$Version"

    if ($Script.EndsWith('.nu')) {
        if (-not (Get-Command -ErrorAction SilentlyContinue nu)) {
            $NushellArgs = ''
            if ($TargetEnv -eq 'Machine') {
                $NushellArgs = "$NushellArgs --global"
            }
            if ($PreserveEnv) {
                $NushellArgs = "$NushellArgs --preserve-env"
            }

            $NushellScript = Invoke-WebRequest -UseBasicParsing -Uri `
                "$URL/src/install/nushell.ps1"
            Invoke-Expression "& { $NushellScript } $NushellArgs"
        }

        Set-Content -Path "$DestDir\$Name.bat" -Value @"
@echo off
nu "$DestDir\$Script" %*
exit /b %errorlevel%
"@
    }
    if ($Script.EndsWith('.py')) {
        if (-not (Get-Command -ErrorAction SilentlyContinue uv)) {
            $UvArgs = ''
            if ($TargetEnv -eq 'Machine') {
                $UvArgs = "$UvArgs --global"
            }
            if ($PreserveEnv) {
                $UvArgs = "$UvArgs --preserve-env"
            }

            $UvScript = Invoke-WebRequest -UseBasicParsing -Uri `
                "$URL/src/install/uv.ps1"
            Invoke-Expression "& { $UvScript } $UvArgs"
        }

        Set-Content -Path "$DestDir\$Name.bat" -Value @"
@echo off
uv --no-config run --script "$DestDir\$Script" %*
exit /b %errorlevel%
"@
    }
    if ($Script.EndsWith('.ts')) {
        if (-not (Get-Command -ErrorAction SilentlyContinue deno)) {
            $DenoArgs = ''
            if ($TargetEnv -eq 'Machine') {
                $DenoArgs = "$DenoArgs --global"
            }
            if ($PreserveEnv) {
                $DenoArgs = "$DenoArgs --preserve-env"
            }

            $DenoScript = Invoke-WebRequest -UseBasicParsing -Uri `
                "$URL/src/install/deno.ps1"
            Invoke-Expression "& { $DenoScript } $DenoArgs"
        }

        Set-Content -Path "$DestDir\$Name.bat" -Value @"
@echo off
deno run --allow-all "$DestDir\$Script" %*
exit /b %errorlevel%
"@
    }
    else {
        Set-Content -Path "$DestDir\$Name.bat" -Value @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$DestDir\$Script" %*
exit /b %errorlevel%
"@
    }

    Log "Installing script $Name to '$DestDir\$Name'."
    Invoke-WebRequest -UseBasicParsing -OutFile "$DestDir\$Script" `
        -Uri "$URL/src/script/$Script"

    if (-not $PreserveEnv) {
        $Path = [Environment]::GetEnvironmentVariable('Path', "$TargetEnv")
        if (-not ($Path -like "*$DestDir*")) {
            $PrependedPath = "$DestDir;$Path"
            [System.Environment]::SetEnvironmentVariable(
                'Path', "$PrependedPath", "$TargetEnv"
            )
            Log "Added '$DestDir' to the system path."
            Log 'Source shell profile or restart shell after installation.'
        }
    }

    $Env:Path = "$DestDir;$Env:Path"
    Log "Installed $(& $Name --version)."
}

# Print message if logging is enabled.
function Log($Text) {
    if (!"$Env:SCRIPTS_NOLOG") {
        Write-Output $Text
    }
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0
    $DestDir = ''
    $List = $False
    $PreserveEnv = $False
    $Names = @()
    $Version = 'main'

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-d', '--dest' } {
                $DestDir = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            { $_ -in '-g', '--global' } {
                if (-not $DestDir) {
                    $DestDir = 'C:\Program Files\Bin'
                }
                $ArgIdx += 1
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
            { $_ -in '-p', '--preserve-env' } {
                $PreserveEnv = $True
                $ArgIdx += 1
                break
            }
            { $_ -in '-q', '--quiet' } {
                $Env:SCRIPTS_NOLOG = 'true'
                $ArgIdx += 1
                break
            }
            { $_ -in '-v', '--version' } {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                break
            }
            default {
                $Names += $Args[0][$ArgIdx]
                $ArgIdx += 1
            }
        }
    }

    $Scripts = FindScripts "$Version"
    if ($List) {
        foreach ($Script in $Scripts) {
            Write-Output "$([IO.Path]::GetFileNameWithoutExtension($Script))"
        }
    }
    elseif ($Names) {
        # Create destination folder if it does not exist for Resolve-Path.
        if (-not $DestDir) {
            $DestDir = "$Env:LocalAppData\Programs\Bin"
        }
        New-Item -Force -ItemType Directory -Path $DestDir | Out-Null

        # Set environment target on whether destination is inside user home
        # folder.
        $DestDir = $(Resolve-Path -Path $DestDir).Path
        $HomeDir = $(Resolve-Path -Path $HOME).Path
        if ($DestDir.StartsWith($HomeDir)) {
            $TargetEnv = 'User'
        }
        else {
            $TargetEnv = 'Machine'
        }

        foreach ($Name in $Names) {
            $MatchFound = $False
            foreach ($Script in $Scripts) {
                $ScriptName = [IO.Path]::GetFileNameWithoutExtension($Script)
                if ($ScriptName -eq $Name) {
                    $MatchFound = $True
                    InstallScript $TargetEnv $Version $DestDir $Script `
                        $PreserveEnv
                }
            }

            if (-not $MatchFound) {
                throw "Error: No script name match found for '$Name'"
            }
        }
    }
    else {
        Log 'error: Script argument required.'
        Log "Run 'install-scripts --help' for usage."
        exit 2
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
