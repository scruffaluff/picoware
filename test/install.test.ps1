# Tests for PowerShell installer scripts.

BeforeAll {
    Set-Location $([System.IO.Path]::GetFullPath("$PSScriptRoot\.."))

    function MkTempDir() {
        $TempDir = Join-Path $Env:Temp $([Guid]::NewGuid())
        New-Item -Path $TempDir -Type Directory | Out-Null
        $TempDir
    }
}

Describe 'Install' {
    It 'Deno prints version' {
        $TempDir = MkTempDir
        $Actual = & src\install\deno.ps1 --preserve-env --dest $TempDir
        $($Actual -join "`n") | Should -Match 'Installed deno 2.'
        Remove-Item -Recurse -Force $TempDir | Out-Null
    }

    It 'Jq prints version' {
        $TempDir = MkTempDir
        $Actual = & src\install\jq.ps1 --preserve-env --dest $TempDir
        $($Actual -join "`n") | Should -Match 'Installed jq-1.'
        Remove-Item -Recurse -Force $TempDir | Out-Null
    }

    It 'Just prints version' {
        $TempDir = MkTempDir
        $Actual = & src\install\just.ps1 --preserve-env --dest $TempDir
        $($Actual -join "`n") | Should -Match 'Installed just 1.'
        Remove-Item -Recurse -Force $TempDir | Out-Null
    }

    It 'Just downloads Jq if missing' {
        Mock Get-Command { $False }
        $TempDir = MkTempDir
        $Actual = & src\install\just.ps1 --preserve-env --dest $TempDir
        $($Actual -join "`n") | Should -Match 'Installed just 1.'
        Remove-Item -Recurse -Force $TempDir | Out-Null
    }

    It 'Just shows error usage for bad argument' {
        $Actual = & src\install\just.ps1 --preserve-env --dst
        $Actual | Should -Be @(
            "error: No such option '--dst'."
            "Run 'install-just --help' for usage."
        )
    }

    It 'Nushell prints version' {
        $TempDir = MkTempDir
        $Actual = & src\install\nushell.ps1 --preserve-env --dest $TempDir
        $($Actual -join "`n") | Should -Match 'Installed Nushell 0.'
        Remove-Item -Recurse -Force $TempDir | Out-Null
    }

    It 'Rust Script prints version' {
        $TempDir = MkTempDir
        $Actual = & src\install\rust-script.ps1 --preserve-env --dest $TempDir
        $($Actual -join "`n") | Should -Match 'Installed rust-script 0.'
        Remove-Item -Recurse -Force $TempDir | Out-Null
    }

    It 'Uv prints version' {
        $TempDir = MkTempDir
        $Actual = & src\install\uv.ps1 --preserve-env --dest $TempDir
        $($Actual -join "`n") | Should -Match 'Installed uv 0.'
        Remove-Item -Recurse -Force $TempDir | Out-Null
    }
}
