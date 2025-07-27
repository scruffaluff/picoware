#!/usr/bin/env sh
#
# SSH for one time remote connections.

# Exit immediately if a command exits with non-zero return code.
#
# Flags:
#   -e: Exit immediately when a command pipeline fails.
#   -u: Throw an error when an unset variable is encountered.
set -eu

#######################################
# Show CLI help information.
# Outputs:
#   Writes help information to stdout.
#######################################
usage() {
  cat 1>&2 << EOF
SSH for one time remote connections.

Usage: tssh [OPTIONS] [ARGS]...

Options:
      --debug     Show shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information
EOF
  if [ -x "$(command -v ssh)" ]; then
    printf '\nSSH Options:\n'
    ssh
  fi
}

#######################################
# Print Tssh version string.
# Outputs:
#   Tssh version string.
#######################################
version() {
  echo 'Tssh 0.3.0'
}

#######################################
# Script entrypoint.
#######################################
main() {
  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -h | --help)
        usage
        return
        ;;
      -v | --version)
        version
        return
        ;;
      *)
        ssh \
          -o IdentitiesOnly=yes \
          -o LogLevel=ERROR \
          -o PreferredAuthentications=publickey,password \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          "$@"
        return
        ;;
    esac
  done

  usage
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
