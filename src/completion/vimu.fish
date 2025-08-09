# Fish completion file for Vimu.
#
# For a tutorial on writing Fish completions, visit
# https://fishshell.com/docs/current/completions.html.

complete --command vimu --wraps virsh
complete --command vimu --description 'Print help information' --long-option \
    help --short-option h
complete --command vimu --description 'Print version information' \
    --long-option version --short-option v
