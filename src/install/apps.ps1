<#
.SYNOPSIS
    Installs Scripts apps for Windows systems.
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
Installer script for Scripts apps.

Usage: install-apps [OPTIONS] <APPS>...

Options:
  -g, --global              Install apps for all users
  -h, --help                Print help information
  -l, --list                List all available apps
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of apps to install
'@
}

# Capitalize app name.
function Capitalize($Name) {
    $Words = $Name -replace '_', ' '
    $(Get-Culture).TextInfo.ToTitleCase($Words)
}

# Download application from repository.
function FetchApp($Version, $Name, $Dest) {
    $Filter = ".tree[] | select(.type == \`"blob\`") | .path | select(startswith(\`"src/app/$Name/\`")) | ltrimstr(\`"src/app/$Name/\`")"
    $Url = "https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/$Version/src/app/$Name"

    $JqBin = FindJq
    $Response = Invoke-WebRequest -UseBasicParsing -Uri `
        "https://api.github.com/repos/scruffaluff/scripts/git/trees/$Version`?recursive=true"
    $Files = "$Response" | & $JqBin --exit-status --raw-output "$Filter"

    foreach ($File in $Files) {
        if (
            $File.EndsWith('.nu') -or $File.EndsWith('.ps1') -or
            $File.EndsWith('.py') -or $File.EndsWith('.rs') -or $File.EndsWith('.ts')
        ) {
            $DestFile = "$Dest\$File"
            $Script = $DestFile
        }
        else {
            $DestFile = "$Dest\$File"
        }

        Invoke-WebRequest -UseBasicParsing -OutFile $DestFile -Uri "$Url/$File"
    }

    $Script
}

# Find all apps inside repository.
function FindApps($Version) {
    $Filter = '.tree[] | select(.type == \"tree\") | .path | select(startswith(\"src/app/\")) | ltrimstr(\"src/app/\")'
    $JqBin = FindJq
    $Response = Invoke-WebRequest -UseBasicParsing -Uri `
        "https://api.github.com/repos/scruffaluff/scripts/git/trees/$Version`?recursive=true"
    "$Response" | & $JqBin --exit-status --raw-output "$Filter"
}

# Find or download Jq JSON parser.
function FindJq() {
    $JqBin = $(Get-Command -ErrorAction SilentlyContinue jq).Source
    if ($JqBin) {
        $JqBin
    }
    else {
        $Arch = $Env:PROCESSOR_ARCHITECTURE.ToLower()
        $TempFile = [System.IO.Path]::GetTempFileName() -replace '.tmp', '.exe'
        Invoke-WebRequest -UseBasicParsing -OutFile $TempFile -Uri `
            "https://github.com/jqlang/jq/releases/latest/download/jq-windows-$Arch.exe"
        $TempFile
    }
}

# Install application.
function InstallApp($Target, $Version, $Name) {
    $Url = "https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/$Version"
    $Title = Capitalize $Name

    if ($Target -eq 'User') {
        $CliDir = "$Env:LocalAppData\Programs\Bin"
        $DestDir = "$Env:LocalAppData\Programs\App\$Name"
        $MenuDir = "$Env:AppData\Microsoft\Windows\Start Menu\Programs\App"
    }
    else {
        $CliDir = 'C:\Program Files\Bin'
        $DestDir = "C:\Program Files\App\$Name"
        $MenuDir = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\App'
    }
    New-Item -Force -ItemType Directory -Path $CliDir | Out-Null
    New-Item -Force -ItemType Directory -Path $DestDir | Out-Null
    New-Item -Force -ItemType Directory -Path $MenuDir | Out-Null

    Log "Installing app $Title."
    Invoke-WebRequest -UseBasicParsing -OutFile "$DestDir\icon.ico" -Uri `
        "$Url/data/public/favicon.ico"
    $Script = FetchApp $Version $Name $DestDir
    SetupRunner $Name $Script $DestDir $CliDir

    # TODO: Document why this is needed.
    $Acl = Get-Acl $DestDir
    $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Env:USER,
        "FullControl",
        "Allow"
    )
    $Acl.AddAccessRule($AccessRule)
    Set-Acl $DestDir $Acl

    # Update path variable if CLI is not in system path.
    $Path = [Environment]::GetEnvironmentVariable('Path', "$TargetEnv")
    if (-not ($Path -like "*$CliDir*")) {
        $PrependedPath = "$CliDir;$Path"
        [System.Environment]::SetEnvironmentVariable(
            'Path', "$PrependedPath", "$TargetEnv"
        )
        Log "Added '$CliDir' to the system path."
        Log 'Source shell profile or restart shell after installation.'
    }

    $Env:Path = "$CliDir;$Env:Path"
    Log "Installed $(& $Name --version)."
}

# Check if script is run from an admin console.
function IsAdministrator {
    ([Security.Principal.WindowsPrincipal]`
        [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Print message if logging is enabled.
function Log($Text) {
    if (!"$Env:SCRIPTS_NOLOG") {
        Write-Output $Text
    }
}

# Find application runner.
function SetupRunner($Name, $Script, $DestDir, $CliDir) {
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

        $Arguments = "`"$Script`""
        $Runner = $(Get-Command nu).Source
    }
    elseif ($Script.EndsWith('.py')) {
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

        $Arguments = "--no-config --quiet run --script `"$Script`""
        $Runner = $(Get-Command uv).Source
    }
    elseif ($Script.EndsWith('.ts')) {
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

        $Arguments = "run --allow-all --no-config --quiet --node-modules-dir=none `"$Script`""
        $Runner = $(Get-Command deno).Source
    }
    else {
        $Arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$Script`""
        $Runner = $(Get-Command powershell).Source
    }

    Set-Content -Path "$CliDir\$Name.cmd" -Value @"
@echo off
"$Runner" $Arguments %*
"@

    # Based on guide at
    # https://learn.microsoft.com/en-us/troubleshoot/windows-client/admin-development/create-desktop-shortcut-with-wsh.
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$MenuDir\$Title.lnk")
    $Shortcut.Arguments = $Arguments
    $Shortcut.IconLocation = "$DestDir\icon.ico"
    $Shortcut.TargetPath = $Runner
    $Shortcut.WindowStyle = 7 # Minimize initial terminal flash.
    $Shortcut.Save()
}

# Script entrypoint.
function Main() {
    $ArgIdx = 0
    $List = $False
    $Names = @()
    $TargetEnv = 'User'
    $Version = 'main'

    while ($ArgIdx -lt $Args[0].Count) {
        switch ($Args[0][$ArgIdx]) {
            { $_ -in '-g', '--global' } {
                $TargetEnv = 'Machine'
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

    $Apps = FindApps "$Version"
    if ($List) {
        foreach ($App in $Apps) {
            Write-Output "$([IO.Path]::GetFileNameWithoutExtension($App))"
        }
    }
    elseif ($Names) {
        if (($TargetEnv -eq 'Machine') -and (-not (IsAdministrator))) {
            Log @'
System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
'@
            exit 1
        }

        foreach ($Name in $Names) {
            $MatchFound = $False
            foreach ($App in $Apps) {
                $AppName = [IO.Path]::GetFileNameWithoutExtension($App)
                if ($AppName -eq $Name) {
                    $MatchFound = $True
                    InstallApp $TargetEnv $Version $App
                }
            }

            if (-not $MatchFound) {
                throw "error: No script name match found for '$Name'"
            }
        }
    }
    else {
        Log 'error: App argument required.'
        Log "Run 'install-apps --help' for usage."
        exit 2
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
if ($MyInvocation.InvocationName -ne '.') {
    Main $Args
}
