# Fish completion file for Tssh.
#
# For a tutorial on writing Fish completions, visit
# https://fishshell.com/docs/current/completions.html.

complete --command tssh --wraps ssh
complete --command tssh --description 'Print help information' --long-option \
    help --short-option h
complete --command tssh --description 'Print version information' \
    --long-option version --short-option v
