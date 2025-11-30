#!/usr/bin/env sh
#
# Frees up disk space by clearing caches of several package managers.

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
Frees up disk space by clearing caches of package managers.

Usage: clear-cache [OPTIONS]

Options:
      --debug     Show shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information
EOF
}

#######################################
# Clear cache of all package managers.
#######################################
clear_cache() {
  local super
  super="$(find_super)"

  # Do not quote the outer super parameter expansion. Shell will error due to be
  # being unable to find the "" command.
  if command -v apk > /dev/null 2>&1; then
    ${super:+"${super}"} apk cache clean
  fi

  if command -v apt-get > /dev/null 2>&1; then
    # Avoid APT interactive configuration requests.
    export DEBIAN_FRONTEND='noninteractive'
    ${super:+"${super}" -E} apt-get clean --yes
  fi

  if command -v brew > /dev/null 2>&1; then
    brew cleanup --prune all
  fi

  if command -v dnf > /dev/null 2>&1; then
    ${super:+"${super}"} dnf clean --assumeyes all
  fi

  if command -v flatpak > /dev/null 2>&1; then
    ${super:+"${super}"} flatpak uninstall --assumeyes --unused
  fi

  if command -v pacman > /dev/null 2>&1; then
    ${super:+"${super}"} pacman --clean --sync
  fi

  if command -v pkg > /dev/null 2>&1; then
    ${super:+"${super}"} pkg clean --all --yes
  fi

  if command -v zypper > /dev/null 2>&1; then
    ${super:+"${super}"} zypper clean --all
  fi

  if command -v cargo-cache > /dev/null 2>&1; then
    cargo-cache --autoclean
  fi

  # Check if Docker client is install and Docker daemon is up and running.
  if command -v docker > /dev/null 2>&1 && docker ps > /dev/null 2>&1; then
    ${super:+"${super}"} docker system prune --force --volumes
  fi

  if command -v npm > /dev/null 2>&1; then
    npm cache clean --force --loglevel error
  fi

  if command -v nvm > /dev/null 2>&1; then
    nvm cache clear
  fi

  if command -v pip > /dev/null 2>&1; then
    pip cache purge
  fi

  if command -v playwright > /dev/null 2>&1; then
    clear_playwright
  fi

  if command -v poetry > /dev/null 2>&1; then
    for cache in $(poetry cache list); do
      poetry cache clear --all --no-interaction "${cache}"
    done
  fi
}

#######################################
# Clear cache for Playwright.
#######################################
clear_playwright() {
  # Do not use long form flags for uname. They are not supported on some
  # systems.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  #   -s: Show operating system kernel name.
  if [ "$(uname -s)" = 'Darwin' ]; then
    if [ -d "${HOME}/Library/Caches/ms-playwright/.links" ]; then
      playwright uninstall --all
    fi
  elif [ -d "${HOME}/.cache/ms-playwright/.links" ]; then
    playwright uninstall --all
  fi
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
  elif command -v doas > /dev/null 2>&1; then
    echo 'doas'
  elif command -v sudo > /dev/null 2>&1; then
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
# Print Clear Cache version string.
# Outputs:
#   Clear Cache version string.
#######################################
version() {
  echo 'Clear Cache 0.3.0'
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
        log --stderr "Run 'clear-cache --help' for usage."
        exit 2
        ;;
    esac
  done

  clear_cache
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
