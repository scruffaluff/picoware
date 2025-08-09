# Fish completion file for Rgi.
#
# For a tutorial on writing Fish completions, visit
# https://fishshell.com/docs/current/completions.html.

complete --command rgi --wraps rg
complete --command rgi --description 'Open selection in default editor' \
    --long-option edit
complete --command rgi --description 'Print help information' --long-option \
    help --short-option h
complete --command rgi --description 'Print version information' --long-option \
    version --short-option v
