#!/usr/bin/env nu

# Interactive Ripgrep searcher.
def --wrapped main [
    --edit # Open selection in default editor
    ...args: string # Ripgrep arguments.
] {
    if ($args | is-empty) {
        rg
    } else if ("-h" in $args) or ("--help" in $args) {
        (
            print
"Interactive Ripgrep searcher.

Usage: rgi [OPTIONS]

Options:
      --edit        Open selection in default editor
  -h, --help        Print help information
  -v, --version     Print version information

Ripgrep Options:
"
        )
        rg --help
        return
    } else if ("-v" in $args) or ("--version" in $args) {
        print "Rgi 0.2.0"
        return
    }

    let editor = $env.EDITOR? | default "vim"
    mut fzf_args = []
    if ($edit) {
        $fzf_args = (
            [...$fzf_args "--bind" $"enter:execute\(($editor) +{2} {1}\)"]
        )
    }

    # Single quotes are used to prevent expansion of glob and regex arguments.
    let arguments = if $nu.os-info.name == "windows" {
        $args | each {|arg| $arg | str replace --all "'" "''" }
    } else {
        $args | each {|arg| $arg | str replace --all "'" "\\'" }
    }
    let command = (
        "rg --column --line-number --no-heading --smart-case --color always "
        + $"'($arguments | str join "' '")'"
    )

    let preview = if (which bat | is-empty) {
        "less +{2} {1}"
    } else {
        "bat --color always --highlight-line {2} --style numbers {1}"
    }
    (
        fzf --ansi --border --exit-0 --reverse --accept-nth -1
        --bind $"start:reload:($command)" --delimiter ":"
        --preview $preview --preview-window "up,60%,border-bottom,+{2}/2"
        --with-shell "nu --commands" ...$fzf_args
    )
}
