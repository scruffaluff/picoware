# Tests for Nushell installer scripts.

use std/assert
use std/testing *

@test
def deno_prints_version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/deno.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0
    assert str contains $result.stdout "Installed deno 2."
}

@test
def deno_global_owner_is_root [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/deno.nu --global --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0

    if $nu.os-info.name != "windows" {
        let owner = stat -c '%U' /usr/local/bin/aws_completer
        assert equal $owner "root"
    }
}

@test
def deno_quiet_is_silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/deno.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0
    assert equal $result.stdout ""
}
