# Tests for PowerShell installer scripts.

BeforeAll {
    Set-Location $([System.IO.Path]::GetFullPath("$PSScriptRoot\.."))

    function MkTempDir() {
        $TempDir = Join-Path $Env:Temp $([Guid]::NewGuid())
        New-Item -Type Directory -Path $TempDir | Out-Null
        $TempDir
    }
}

Describe 'Install' {
    It 'Deno prints version' {
        $Actual = & src\install\deno.ps1 --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed deno 2.'
    }

    It 'Jq prints version' {
        $Actual = & src\install\jq.ps1 --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed jq-1.'
    }

    It 'Just prints version' {
        $Actual = & src\install\just.ps1 --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed just 1.'
    }

    It 'Just downloads Jq is missing' {
        Mock Get-Command { $False }
        $Actual = & src\install\just.ps1 --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed just 1.'
    }

    It 'Just shows error usage for bad argument' {
        $Actual = & src\install\just.ps1 --preserve-env --dst
        $Actual | Should -Be @(
            "error: No such option '--dst'."
            "Run 'install-just --help' for usage."
        )
    }

    It 'Nushell prints version' {
        $Actual = & src\install\nushell.ps1 --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed Nushell 0.'
    }

    It 'Uv prints version' {
        $Actual = & src\install\uv.ps1 --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed uv 0.'
    }
}
