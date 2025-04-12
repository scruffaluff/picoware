#!/usr/bin/env nu
#
# Interactive Ripgrep searcher based on logic from
# https://github.com/junegunn/fzf/blob/master/ADVANCED.md#using-fzf-as-interactive-ripgrep-launcher.

# Interactive Ripgrep searcher.
def --wrapped main [...args: string] {
    if ($args | is-empty) {
        rg
    } else if ("-h" in $args) or ("--help" in $args) {
        rg --help
        exit 0
    } else if ("-v" in $args) or ("--version" in $args) {
        print "Rgi 0.1.0"
        exit 0
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

    let editor = $env.EDITOR? | default "vim"
    (
        fzf --ansi
        --bind $"enter:become\(($editor) +{2} {1}\)"
        --bind $"start:reload:($command)"
        --delimiter ":"
        --exit-0
        --preview "bat --color always --highlight-line {2} {1}"
        --preview-window 'up,60%,border-bottom,+{2}/2'

    )
}
