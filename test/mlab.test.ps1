Describe 'Install' {
    BeforeAll {
        # Path normalization required for Assert-MockCalled parameter filters.
        $Mlab = [System.IO.Path]::GetFullPath("$PSScriptRoot/../src/script/mlab.ps1")
        . "$Mlab"

        $Env:MLAB_PROGRAM = 'C:/Windows/matlab'
        $Env:SCRIPTS_NOLOG = 'true'
    }

    It 'Mlab argumentless call contains no commands' {
        $Expected = '& C:/Windows/matlab -nodisplay -nosplash'

        $Actual = & $Mlab run --echo
        $Actual | Should -Be $Expected
    }

    It 'Mlab debug call contains sets breakpoint on error' {
        $Expected = '& C:/Windows/matlab -nodisplay -nosplash ' `
            + '-r dbstop if error;'

        $Actual = & $Mlab run --echo --debug
        $Actual | Should -Be $Expected
    }

    It 'Mlab function call contains one batch command' {
        $Expected = '& C:/Windows/matlab -nodesktop -nosplash -batch script'

        $Actual = & $Mlab run --echo script
        $Actual | Should -Be $Expected
    }

    It 'Mlab genpath option call contains multiple path commands' {
        $Expected = '& C:/Windows/matlab -nodisplay -nosplash ' `
            + "-r addpath(genpath('/tmp')); "

        $Actual = & $Mlab run --echo --genpath /tmp
        $Actual | Should -Be $Expected
    }

    It 'Mlab path option call contains path command' {
        $Expected = '& C:/Windows/matlab -nodisplay -nosplash ' `
            + "-r addpath('/tmp'); "

        $Actual = & $Mlab run --echo --addpath /tmp
        $Actual | Should -Be $Expected
    }

    It 'Mlab script call contains one batch command' {
        $Expected = '& C:/Windows/matlab -nodesktop -nosplash ' `
            + "-batch addpath('src'); script"

        $Actual = & $Mlab run --echo src/script.m
        $Actual | Should -Be $Expected
    }

    It 'Mlab debug script call contains several commands' {
        $Expected = '& C:/Windows/matlab -nodisplay -nosplash ' `
            + "-r addpath('src'); dbstop if error; dbstop in script; " `
            + 'script; exit'

        $Actual = & $Mlab run --echo --debug src/script.m
        $Actual | Should -Be $Expected
    }
}
