# Fish completion file for Trsync.
#
# For a tutorial on writing Fish completions, visit
# https://fishshell.com/docs/current/completions.html.

complete --command trsync --wraps rsync
complete --command trsync --description 'Print help information' --long-option \
    help --short-option h
complete --command trsync --description 'Print version information' \
    --long-option version --short-option v
