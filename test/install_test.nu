# Tests for Nushell installer scripts.

use std/assert
use std/testing *

@test
def test_deno_prints_version [] {
    let result = nu src/install/deno.nu --preserve-env --dest (mktemp --directory --tmpdir)
    | complete
    assert equal $result.exit_code 0
    assert str contains $result.stdout "Installed deno 2."
}
