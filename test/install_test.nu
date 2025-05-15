# Tests for Nushell installer scripts.

use std/assert
use std/testing *

@test
def deno_prints_version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/deno.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Installed deno 2."
}

@test
def deno_quiet_is_silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/deno.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert equal $result.stdout ""
}

@test
def just_prints_version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/just.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Installed just 1."
}

@test
def just_quiet_is_silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/just.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert equal $result.stdout ""
}

@test
def uv_prints_version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/uv.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Installed uv 0."
}

@test
def uv_quiet_is_silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/uv.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert equal $result.stdout ""
}
