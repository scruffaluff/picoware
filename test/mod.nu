# Reusable testing functions.

# Assert that path exists.
export def "assert path" [path: path, message?: string] {
    (
        assert --error-label {
            span: (metadata $path).span
            text: $"Path '($path)' does not exist"
        } ($path | path exists) $message
    )
}

# Mock env program to fail if "-S" flag is used.
export def --env mock-env [] {
    let text = '
#!/bin/sh
if [ "$1" = "-S" ]; then
  exit 1
fi
'
    | str trim
    mock-prog "env" $text
}

# Mock env program to fail if "-S" flag is used.
export def --env mock-prog [name: string text: string] {
    let temp = mktemp --directory --tmpdir
    $text | save $"($temp)/($name)"
    if $nu.os-info.name != "windows" {
        chmod +x $"($temp)/env"
    }
    $env.PATH = [$temp ...$env.PATH]
}
