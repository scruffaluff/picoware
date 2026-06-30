# Tests for Vimu script.

use std/assert
use std/testing *
use . *

source ../src/install/script.nu

def "http get" [url: string] {
    open data/test/github_trees.json
}

@test
def handle-shebang-creates-shell-wrapper [] {
    if $nu.os-info.name == "windows" {
        return
    }

    let temp = mktemp --directory --tmpdir
    let script = $"($temp)/main"
    "#!/usr/bin/env -S uv --no-config --quiet run --script"
    | save $script

    mock-env
    handle-shebang "" $script "py"
    let text = open --raw $script
    assert path $"($script).py"
    assert str contains $text $"exec uv --no-config --quiet run --script '($script).py' \"$@\""
}

@test
def json-parser-finds-all-scripts [] {
    if $nu.os-info.name == "windows" {
        return
    }

    let scripts = find-scripts "main"
    assert equal $scripts [
        "mockscript.sh"
        "newscript.nu"
        "otherscript.sh"
        "pyscript.py"
    ]
}
