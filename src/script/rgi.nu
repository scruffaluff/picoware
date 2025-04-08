#!/usr/bin/env nu
#
# Uses event bindings described at
# https://junegunn.github.io/fzf/reference/#keyevent-bindings. Interactive Ripgrep
# searcher based on logic from
# https://github.com/junegunn/fzf/blob/master/ADVANCED.md#using-fzf-as-interactive-ripgrep-launcher.

# Interactive Ripgrep searcher.
def --wrapped main [...args: string] {
    if ($args | is-empty) {
        rg
    } else if ("-h" in $args) or ("--help" in $args) {
        rg --help
        exit 0
    } else if ("-v" in $args) or ("--version" in $args) {
        print "Rgi 0.0.3"
        exit 0
    }

    let editor = $env.EDITOR | default "vim"
    # Single quotes are used to prevent expansion of glob and regex arguments.
    let command = (
        "rg --column --line-number --no-heading --smart-case --color always "
        + $"'($args | str join "' '")'"
    )

    (
        fzf --ansi
        --bind $"enter:become\(($editor) +{2} {1}\)"
        --bind $"start:reload:($command)"
        --delimiter ':'
        --exit-0
        --preview 'bat --color always --highlight-line {2} {1}'
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3'

    )
}
