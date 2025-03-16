#!/usr/bin/env sh
#
# Invokes upgrade commands to several package managers.

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
Invokes upgrade commands to all installed package managers.

Usage: packup [OPTIONS]

Options:
      --debug     Show shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information
EOF
}

#######################################
# Update dnf package lists.
#
# DNF's check-update command will give a 100 exit code if there are packages
# available to update. Thus both 0 and 100 must be treated as successful exit
# codes.
#
# Arguments:
#   Super user command for installation.
#######################################
dnf_check_update() {
  ${1:+"${1}"} dnf check-update || {
    code="$?"
    [ "${code}" -eq 100 ] && return 0
    return "${code}"
  }
}

#######################################
# Print error message and exit script with error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error() {
  bold_red='\033[1;31m' default='\033[0m'
  # Flags:
  #   -t <FD>: Check if file descriptor is a terminal.
  if [ -t 2 ]; then
    printf "${bold_red}error${default}: %s\n" "${1}" >&2
  else
    printf "error: %s\n" "${1}" >&2
  fi
  exit 1
}

#######################################
# Print error message and exit script with usage error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error_usage() {
  bold_red='\033[1;31m' default='\033[0m'
  # Flags:
  #   -t <FD>: Check if file descriptor is a terminal.
  if [ -t 2 ]; then
    printf "${bold_red}error${default}: %s\n" "${1}" >&2
  else
    printf "error: %s\n" "${1}" >&2
  fi
  printf "Run 'packup --help' for usage.\n" >&2
  exit 2
}

#######################################
# Find command to elevate as super user.
#######################################
find_super() {
  # Do not use long form -user flag for id. It is not supported on MacOS.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ "$(id -u)" -eq 0 ]; then
    echo ''
  elif [ -x "$(command -v sudo)" ]; then
    echo 'sudo'
  elif [ -x "$(command -v doas)" ]; then
    echo 'doas'
  else
    error 'Unable to find a command for super user elevation'
  fi
}

#######################################
# Invoke upgrade commands to all installed package managers.
#######################################
upgrade() {
  super="$(find_super)"

  # Do not quote the outer super parameter expansion. Shell will error due to be
  # being unable to find the "" command.
  if [ -x "$(command -v apk)" ]; then
    ${super:+"${super}"} apk update
    ${super:+"${super}"} apk upgrade
  fi

  if [ -x "$(command -v apt-get)" ]; then
    # DEBIAN_FRONTEND variable setting is ineffective if on a separate line,
    # since the command is executed as super user.
    ${super:+"${super}"} apt-get update
    ${super:+"${super}"} DEBIAN_FRONTEND=noninteractive apt-get full-upgrade \
      --yes --allow-downgrades
    ${super:+"${super}"} apt-get autoremove --yes
  fi

  if [ -x "$(command -v brew)" ]; then
    brew update
    brew upgrade --greedy
  fi

  if [ -x "$(command -v dnf)" ]; then
    dnf_check_update "${super}"
    ${super:+"${super}"} dnf upgrade --assumeyes
    ${super:+"${super}"} dnf autoremove --assumeyes
  fi

  if [ -x "$(command -v flatpak)" ]; then
    ${super:+"${super}"} flatpak update --assumeyes
  fi

  if [ -x "$(command -v opkg)" ]; then
    ${super:+"${super}"} opkg update
    ${super:+"${super}"} opkg list-upgradable |
      cut -f 1 -d ' ' |
      xargs -r ${super:+"${super}"} opkg upgrade
  fi

  if [ -x "$(command -v pacman)" ]; then
    ${super:+"${super}"} pacman --noconfirm --refresh --sync --sysupgrade
  fi

  if [ -x "$(command -v pkg)" ]; then
    ${super:+"${super}"} pkg update
    ${super:+"${super}"} pkg upgrade --yes
  fi

  if [ -x "$(command -v zypper)" ]; then
    ${super:+"${super}"} zypper update --no-confirm
    ${super:+"${super}"} zypper autoremove --no-confirm
  fi

  if [ -x "$(command -v cargo)" ] && [ -O "$(which cargo)" ]; then
    cargo install --list | while read -r line; do
      # Do not use "^" as the first character of an expr expression. Some
      # versions will throw an error.
      if expr "${line}" : '.*:$' > /dev/null; then
        cargo install "$(echo "${line}" | cut -f1 -d ' ')"
      fi
    done
  fi

  # Flags:
  #   -O: Check if current user owns the file.
  if [ -x "$(command -v npm)" ] && [ -O "$(which npm)" ]; then
    # The 'npm install' command is run before 'npm update' command to avoid
    # messages about newer versions of NPM being available.
    npm install --global npm@latest
    npm update --global --loglevel error
  fi

  if [ -x "$(command -v pipx)" ] && [ -O "$(which pipx)" ]; then
    pipx upgrade-all
  fi

  if [ -x "$(command -v tldr)" ]; then
    tldr --update
  fi

  if [ -x "$(command -v ya)" ]; then
    ya pack --upgrade
  fi
}

#######################################
# Print Packup version string.
# Outputs:
#   Packup version string.
#######################################
version() {
  echo 'Packup 0.4.4'
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
        exit 0
        ;;
      -v | --version)
        version
        exit 0
        ;;
      *)
        error_usage "No such option '${1}'."
        ;;
    esac
  done

  upgrade
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
