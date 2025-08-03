# Tests for Nushell installer scripts.

use std/assert
use std/testing *

@test
def deno-prints=version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/deno.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Installed deno 2."
}

@test
def deno-quiet-is-silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/deno.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert equal $result.stdout ""
}

@test
def jq-prints-version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/jq.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Installed jq-1."
}

@test
def jq-quiet-is-silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/jq.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert equal $result.stdout ""
}

@test
def just-prints-version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/just.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Installed just 1."
}

@test
def just-quiet-is-silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/just.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert equal $result.stdout ""
}

@test
def uv-prints-version [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/uv.nu --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Installed uv 0."
}

@test
def uv-quiet-is-silent [] {
    let tmp_dir = mktemp --directory --tmpdir
    let result = nu src/install/uv.nu --quiet --preserve-env --dest $tmp_dir
    | complete
    assert equal $result.exit_code 0 $result.stderr
    assert equal $result.stdout ""
}
