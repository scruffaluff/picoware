#!/usr/bin/env nu

# Interactive Fd searcher.
def --wrapped main [
    --edit # Open selection in default editor
    ...args: string # Fd arguments.
] {
    if ("-h" in $args) or ("--help" in $args) {
        (
            print
"Interactive Fd searcher.

Usage: fdi [OPTIONS]

Options:
      --edit        Open selection in default editor
  -h, --help        Print help information
  -v, --version     Print version information

Fd Options:
"
        )
        fd ...$args
        return
    } else if ("-v" in $args) or ("--version" in $args) {
        print "Fdi 0.1.0"
        return
    }

    let editor = $env.EDITOR? | default "vim"
    mut fzf_args = []
    if ($edit) {
        $fzf_args = [...$fzf_args "--bind" $"enter:execute\(($editor) {1}\)"]
    }

    # Single quotes are used to prevent expansion of glob and regex arguments.
    let arguments = if $nu.os-info.name == "windows" {
        $args | each {|arg| $arg | str replace --all "'" "''" }
    } else {
        $args | each {|arg| $arg | str replace --all "'" "\\'" }
    }
    let command = (
        "fd --hidden --no-require-git " + $"'($arguments | str join "' '")'"
    )

    let dir_preview = if (which lsd | is-empty) {
        "ls $path | get name | to text"
    } else {
        "lsd --tree --depth 1 $path"
    }
    let file_preview = if (which bat | is-empty) {
        "less $path"
    } else {
        "bat --color always --line-range :100 --style numbers $path"
    }
    let preview = $"do {|path|
        if \($path | path type\) == \"dir\" {
            ($dir_preview)
        } else {
            ($file_preview)
        }
    }"
    (
        fzf --ansi --border --exit-0 --reverse
        --bind $"start:reload:($command)" --preview $"($preview) {}"
        --preview-window "border-left" --with-shell "nu --commands" ...$fzf_args
    )
}
