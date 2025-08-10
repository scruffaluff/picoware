# Fish completion file for Rgi.
#
# For a reference on flags for the Fish complete command,, visit
# https://fishshell.com/docs/current/cmds/complete.html#description.

complete -c rgi -w rg
complete -c rgi -l edit -d 'Open selection in default editor'
complete -c rgi -l help -s h -d 'Print help information'
complete -c rgi -l version -s v -d 'Print version information'
