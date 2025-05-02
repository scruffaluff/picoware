use std/assert

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

# Tests for Nushell Mlab script.
def main [] {
    let test_commands = (
        scope commands
        | where ($it.type == "custom")
            and ($it.name | str starts-with "test_")
            and not ($it.description | str starts-with "ignore")
        | get name
        | each { |test| [$"print 'Running test: ($test)'", $test] }
        | flatten
        | str join "; "
    )

    print "Running tests..."
    nu --commands $"source ($env.CURRENT_FILE); ($test_commands)"
    print "Tests completed successfully"
}

def test_mlab_dump_flags [] {
    $env.MLAB_PROGRAM = mock_matlab
    let result = nu src/script/mlab.nu dump "fakefile.mat" | complete
    assert equal $result.exit_code 0
    assert str contains $result.stdout "-nojvm -nosplash -batch"
}

def test_mlab_run_noargs [] {
    $env.MLAB_PROGRAM = mock_matlab
    let result = nu src/script/mlab.nu run | complete
    assert equal $result.exit_code 0
    assert str contains $result.stdout "-nosplash -nojvm"
}
