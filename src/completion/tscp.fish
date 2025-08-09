# Fish completion file for Tscp.
#
# For a tutorial on writing Fish completions, visit
# https://fishshell.com/docs/current/completions.html.

complete --command tscp --wraps scp
complete --command tscp --description 'Print help information' --long-option \
    help --short-option h
complete --command tscp --description 'Print version information' \
    --long-option version --short-option v
