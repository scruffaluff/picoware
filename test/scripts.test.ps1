# Tests for PowerShell scripts installer.

BeforeAll {
    Set-Location $([System.IO.Path]::GetFullPath("$PSScriptRoot\.."))
    $Scripts = 'src\install\scripts.ps1'
    . $Scripts

    Mock Invoke-WebRequest { Get-Content data\test\github_trees.json }
    Mock IsAdministrator { $False }
}

Describe 'Script' {
    It 'JSON parser finds all unix scripts' {
        $Actual = & $Scripts --list
        $Actual | Should -Be @('mockscript', 'newscript', 'otherscript')
    }

    It 'Installer rejects global destination for local user' {
        $Actual = & $Scripts --preserve-env --global tscp
        $Actual | Should -Be @'
System level installation requires an administrator console.
Restart this script from an administrator console or install to a user directory.
'@
    }
}
