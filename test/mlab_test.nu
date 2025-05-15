# Tests for Mlab script.

use std/assert
use std/testing *

def mock_matlab [] {
    let temp = mktemp --tmpdir --suffix ".cmd"
    if $nu.os-info.name == "windows" {
        "@echo off\necho %*\n" | save --force $temp
    } else {
        "#!/usr/bin/env sh\necho $@" | save --force $temp
        chmod +x $temp
    }
    $temp
}

@test
def test_mlab_dump_flags [] {
    $env.MLAB_PROGRAM = mock_matlab
    let result = nu src/script/mlab.nu dump "fakefile.mat" | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "-nojvm -nosplash -batch"
}

@test
def test_mlab_run_noargs [] {
    $env.MLAB_PROGRAM = mock_matlab
    let result = nu src/script/mlab.nu run | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "-nosplash -nojvm"
}
