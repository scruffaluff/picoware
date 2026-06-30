# Tests for PowerShell apps installer.

BeforeAll {
    Set-Location $([System.IO.Path]::GetFullPath("$PSScriptRoot\.."))
    $Apps = 'src\install\app.ps1'
    . $Apps

    Mock Invoke-WebRequest { Get-Content data\test\github_trees.json }
}

Describe 'Apps' {
    It 'JSON parser finds all apps' {
        $Actual = & $Apps --list
        $Actual | Should -Be @('pyapp', 'rsapp')
    }
}
