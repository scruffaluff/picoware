# Fish completion file for Fdi.
#
# For a tutorial on writing Fish completions, visit
# https://fishshell.com/docs/current/completions.html.

complete --command fdi --wraps fd
complete --command fdi --description 'Open selection in default editor' \
    --long-option edit
complete --command fdi --description 'Print help information' --long-option \
    help --short-option h
complete --command fdi --description 'Print version information' --long-option \
    version --short-option v
