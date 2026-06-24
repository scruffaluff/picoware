# Tests for Vimu script.

use std/assert
use std/testing *

source ../src/install/script.nu

def "http get" [url: string] {
    open data/test/github_trees.json
}

@test
def json-parser-finds-all-scripts [] {
    let ext = if $nu.os-info.name == "windows" { ".ps1" } else { ".sh" }
    let scripts = find-scripts "main"
    assert equal $scripts [
        $"mockscript($ext)"
        "newscript.nu"
        $"otherscript($ext)"
        "pyscript.py"
    ]
}
