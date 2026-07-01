# Tests for Nushell apps installer.

use std/assert
use std/testing *

def "http get" [url: string] {
    open data/test/github_trees.json
}

source ../src/install/app.nu

@test
def create-entry-wraps-shebang [] {
    if $nu.os-info.name == "windows" {
        return
    }

    let temp = mktemp --directory
    let script = $"($temp)/main.ts"
    let entry = $"($temp)/main.sh"

    "#!/usr/bin/env -S program --flag"
    | save --force $script
    create-entry "" $script "/usr/local/bin" $entry

    let text = open --raw $entry
    assert str contains $text 'export PATH="/usr/local/bin:${PATH}"'
    assert str contains $text 'exec program --flag "${folder}/main.ts" "$@"'
}

@test
def json-parser-finds-all-apps [] {
    let apps = find-apps "main"
    assert equal $apps ["pyapp" "rsapp"]
}
