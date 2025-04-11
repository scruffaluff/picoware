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
# Cleanup resources on exit.
#######################################
panic() {
  schema="${HOME}/.local/share/gnome-shell/extensions/caffeine@patapon.info/schemas"

  # Flags:
  #   -d: Check if path exists and is a directory.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v gsettings)" ] && [ -d "${schema}" ]; then
    gsettings --schemadir "${schema}" set org.gnome.shell.extensions.caffeine \
      toggle-state false
  fi
}

#######################################
# Print Caffeinate version string.
# Outputs:
#   Caffeinate version string.
#######################################
version() {
  echo 'Caffeinate 0.1.0'
}

#######################################
# Script entrypoint.
#######################################
main() {
  # Use system caffeinate if it exists.
  if [ -x /usr/bin/caffeinate ]; then
    /usr/bin/caffeinate "$@"
    exit 0
  fi

  case "${1:-}" in
    --debug)
      set -o xtrace
      shift 1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -v | --version)
      version
      exit 0
      ;;
    *) ;;
  esac

  # Schema is required since MacOS can have a gsettings program that does
  # nothing if the glib formula, https://formulae.brew.sh/formula/glib, is
  # installed.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  #   -x: Check if file exists and execute permission is granted.
  schema="${HOME}/.local/share/gnome-shell/extensions/caffeine@patapon.info/schemas"
  if [ -x "$(command -v gsettings)" ] && [ -d "${schema}" ]; then
    gsettings --schemadir "${schema}" set org.gnome.shell.extensions.caffeine \
      toggle-state true

    if [ "${#}" -eq 0 ]; then
      # Sleep inifinity is not supported on all platforms.
      #
      #  For more information, visit https://stackoverflow.com/a/41655546.
      while true; do
        sleep 86400
      done
    else
      "$@"
    fi

    gsettings --schemadir "${schema}" set org.gnome.shell.extensions.caffeine \
      toggle-state false
  else
    log --stderr 'error: Unable to find a supported caffeine backend.'
    exit 1
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  trap panic EXIT
  main "$@"
fi
