# Tests for PowerShell scripts installer.

BeforeAll {
    # RepoRoot is used in all unit tests.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignment", "")]
    $RepoRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot/..")

    Mock Invoke-WebRequest {
        Get-Content "$RepoRoot\data\test\github_trees.json"
    }
}

Describe 'Script' {
    It 'JSON parser finds all unix scripts' {
        $Script = "$RepoRoot\src\install\scripts.ps1"
        $Actual = & $Script --list
        $Actual | Should -Be @('mockscript', 'newscript', 'otherscript')
    }

    It 'Installer rejects global destination for local user' {
        $Script = "$RepoRoot\src\install\scripts.ps1"
        $Actual = & $Script --preserve-env --global tscp
        $Actual | Should -Be @'
System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
'@
    }
}
