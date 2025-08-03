# Tests for Nushell installer scripts.

use std/assert
use std/testing *

source ../src/script/vimu.nu

@test
def vimu-create-entry [] {
    const folder = "src/script" | path expand
    let expected = $"
#!/usr/bin/env sh
set -eu

export PATH=\"($folder):${PATH}\"
exec vimu gui machine
"
    | str trim --left

    let temp = mktemp --tmpdir
    create-entry machine $temp
    let text = open --raw $temp
    assert equal $text $expected
}

@test
def vimu-prints-version [] {
    let result = nu src/script/vimu.nu --version | complete
    assert equal $result.exit_code 0 $result.stderr
    assert str contains $result.stdout "Vimu 0.1.0"
}
