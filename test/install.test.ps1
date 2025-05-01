# Tests for PowerShell installer scripts.

BeforeAll {
    # RepoRoot is used in all unit tests.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignment", "")]
    $RepoRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/..")

    function MkTempDir() {
        $TempDir = Join-Path $Env:Temp $(New-Guid)
        New-Item -Type Directory -Path $TempDir | Out-Null
        $TempDir
    }
}

Describe 'Install' {
    It 'Deno prints version' {
        $Script = "$RepoRoot\src\install\deno.ps1"
        $Actual = & $Script --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed deno 2.'
    }

    It 'Jq prints version' {
        $Script = "$RepoRoot\src\install\jq.ps1"
        $Actual = & $Script --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed jq-1.'
    }

    It 'Just prints version' {
        $Script = "$RepoRoot\src\install\just.ps1"
        $Actual = & $Script --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed just 1.'
    }

    It 'Just shows error usage for bad argument' {
        $Script = "$RepoRoot\src\install\just.ps1"
        $Actual = & $Script --preserve-env --dst
        $Actual | Should -Be @(
            "error: No such option '--dst'."
            "Run 'install-just --help' for usage."
        )
    }

    It 'Nushell prints version' {
        $Script = "$RepoRoot\src\install\nushell.ps1"
        $Actual = & $Script --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed Nushell 0.'
    }

    It 'Uv prints version' {
        $Script = "$RepoRoot\src\install\uv.ps1"
        $Actual = & $Script --preserve-env --dest $(MkTempDir)
        $($Actual -join "`n") | Should -Match 'Installed uv 0.'
    }
}
