#!/usr/bin/env sh
#
# Removes all traces of the Snap package manager.

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
Deletes all Snap packages, uninstalls Snap, and prevents reinstall of Snap.

Usage: purge-snap [OPTIONS]

Options:
      --debug     Show shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information
EOF
}

#######################################
# Find command to elevate as super user.
#######################################
find_snaps() {
  # Find all installed Snap packages.
  #
  # Flags:
  #   --lines +2: Select the 2nd line to the end of the output.
  #   --field 1: Take only the first part of the output.
  snap list 2> /dev/null | tail --lines +2 | cut --delimiter ' ' --field 1
}

#######################################
# Find command to elevate as super user.
# Outputs:
#   Super user command.
#######################################
find_super() {
  # Do not use long form flags for id. They are not supported on some systems.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ "$(id -u)" -eq 0 ]; then
    echo ''
  elif [ -x "$(command -v doas)" ]; then
    echo 'doas'
  elif [ -x "$(command -v sudo)" ]; then
    echo 'sudo'
  else
    log --stderr 'error: Unable to find a command for super user elevation.'
    exit 1
  fi
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
# Remove all traces of Snap from system.
#######################################
purge_snaps() {
  local packages super
  super="$(find_super)"

  # Loop repeatedly over Snap packages until all are removed.
  #
  # Several Snap packages cannot be removed until other packages are removed
  # first. Looping repeatedly allows will remove dependencies and then attempt
  # removing the package again.
  packages="$(find_snaps)"
  while [ -n "${packages}" ]; do
    for package in ${packages}; do
      ${super:+"${super}"} snap remove --purge "${package}" 2> /dev/null || true
    done
    packages="$(find_snaps)"
  done

  # Delete Snap system daemons and services.
  #
  # Do not quote the outer super parameter expansion. Shell will error due to be
  # being unable to find the "" command.
  ${super:+"${super}"} systemctl stop --show-transaction snapd.socket
  ${super:+"${super}"} systemctl stop --show-transaction snapd.service
  ${super:+"${super}"} systemctl disable snapd.service

  # Avoid APT interactive configuration requests.
  export DEBIAN_FRONTEND='noninteractive'

  # Delete Snap package and prevent reinstallation.
  ${super:+"${super}" -E} apt-get purge --yes snapd
  ${super:+"${super}" -E} apt-mark hold snapd
}

#######################################
# Print Purge Snap version string.
# Outputs:
#   Purge Snap version string.
#######################################
version() {
  echo 'PurgeSnap 0.4.0'
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
        log --stderr "error: No such option '${1}'."
        log --stderr "Run 'purge-snap --help' for usage."
        exit 2
        ;;
    esac
  done

  # Purge snaps if installed.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v snap)" ]; then
    purge_snaps
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
