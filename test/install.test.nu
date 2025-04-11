use std/assert

# Tests for Nushell installer scripts.
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

def test_deno_prints_version [] {
    let result = nu src/install/deno.nu --dest (mktemp --directory --tmpdir)
    | complete
    assert equal $result.exit_code 0
    assert str contains $result.stdout "Installed deno 2."
}
