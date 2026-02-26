#!/usr/bin/env sh
#
# Prevent system from sleeping during a program.

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
Prevent the system from sleeping during a command.

Usage: caffeinate [OPTIONS]

Options:
      --debug     Show shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information
EOF
}

#######################################
# Print message if error or logging is enabled.
# Arguments:
#   Message to print.
# Globals:
#   SCRIPTS_NOLOG
# Outputs:
#   Message argument.
#######################################
log() {
  local file='1' newline="\n" text=''

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      -e | --stderr)
        file='2'
        shift 1
        ;;
      -n | --no-newline)
        newline=''
        shift 1
        ;;
      *)
        text="${text}${1}"
        shift 1
        ;;
    esac
  done

  # Print if error or using quiet configuration.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${SCRIPTS_NOLOG:-}" ] || [ "${file}" = '2' ]; then
    printf "%s${newline}" "${text}" >&"${file}"
  fi
}

#######################################
# Print Caffeinate version string.
# Outputs:
#   Caffeinate version string.
#######################################
version() {
  echo 'Caffeinate 0.2.1'
}

#######################################
# Script entrypoint.
#######################################
main() {
  # Use system caffeinate if it exists.
  if [ -x /usr/bin/caffeinate ]; then
    /usr/bin/caffeinate "$@"
    return
  fi

  case "${1:-}" in
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
    *) ;;
  esac

  # Flags:
  #   -x: Check if file exists and execute permission is granted.
  if command -v systemd-inhibit > /dev/null 2>&1; then
    # Older versions of systemd-inhibit do not support the --no-ask-password
    # flag.
    if [ "${#}" -eq 0 ]; then
      # Sleep infinity is not supported on all platforms.
      #
      # For more information, visit https://stackoverflow.com/a/41655546.
      while true; do
        systemd-inhibit --no-legend --no-pager --mode block \
          --what idle:sleep sleep 86400
      done
    else
      systemd-inhibit --no-legend --no-pager --mode block \
        --what idle:sleep "$@"
    fi
  else
    log --stderr 'error: Unable to find a supported caffeine backend.'
    exit 1
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
