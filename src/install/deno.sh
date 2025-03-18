#!/usr/bin/env sh
#
# Install Deno for MacOS and Linux systems. This script differs from
# https://deno.land/install.sh by providing more installation options.

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
Installer script for Deno.

Usage: install-deno [OPTIONS]

Options:
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install Deno
  -g, --global              Install Deno for all users
  -h, --help                Print help information
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Deno to install
EOF
}

#######################################
# Perform network request.
#######################################
fetch() {
  local url='' dst_dir='' dst_file='-' mode='' super=''

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      -d | --dest)
        dst_file="${2}"
        shift 2
        ;;
      -m | --mode)
        mode="${2}"
        shift 2
        ;;
      -s | --super)
        super="${2}"
        shift 2
        ;;
      *)
        url="${1}"
        shift 1
        ;;
    esac
  done

  # Create parent directory if it does not exist.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  if [ "${dst_file}" != '-' ]; then
    dst_dir="$(dirname "${dst_file}")"
    if [ ! -d "${dst_dir}" ]; then
      ${super:+"${super}"} mkdir -p "${dst_dir}"
    fi
  fi

  # Download with Curl or Wget.
  #
  # Flags:
  #   -O <PATH>: Save download to path.
  #   -q: Hide log output.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v curl)" ]; then
    ${super:+"${super}"} curl --fail --location --show-error --silent --output \
      "${dst_file}" "${url}"
  elif [ -x "$(command -v wget)" ]; then
    ${super:+"${super}"} wget -q -O "${dst_file}" "${url}"
  else
    log --stderr 'error: Unable to find a network file downloader.'
    log --stderr 'Install curl, https://curl.se, manually before continuing.'
    exit 1
  fi

  # Change file permissions if chmod parameter was passed.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  if [ -n "${mode:-}" ]; then
    ${super:+"${super}"} chmod "${mode}" "${dst_file}"
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
  elif [ -x "$(command -v sudo)" ]; then
    echo 'sudo'
  elif [ -x "$(command -v doas)" ]; then
    echo 'doas'
  else
    log --stderr 'error: Unable to find a command for super user elevation'
    exit 1
  fi
}

#######################################
# Download and install Deno.
# Arguments:
#   Super user command for installation.
#   Deno version.
#   Destination path.
#######################################
install_deno() {
  local super="${1}" version="${2}" dst_dir="${3}"
  local arch='' dst_file="${dst_dir}/deno" os='' target='' tmp_dir=''

  # Exit early if tar is not installed.
  #
  # Flags:
  #   -v: Only show file path of command.
  if [ ! -x "$(command -v unzip)" ]; then
    log --stderr 'error: Unable to find zip file archiver.'
    log --stderr 'Install zip, https://en.wikipedia.org/wiki/ZIP_(file_format), manually before continuing.'
    exit 1
  fi

  # Parse Deno build target.
  #
  # Do not use long form flags for uname. They are not supported on some
  # systems.
  #
  # Flags:
  #   -m: Show system architecture name.
  #   -s: Show operating system kernel name.
  arch="$(uname -m | sed s/amd64/x86_64/ | sed s/x64/x86_64/ |
    sed s/arm64/aarch64/)"
  os="$(uname -s)"
  case "${os}" in
    Darwin)
      target="${arch}-apple-darwin"
      ;;
    Linux)
      target="${arch}-unknown-linux-gnu"
      ;;
    *)
      log --stderr "error: Unsupported operating system '${os}'."
      exit 1
      ;;
  esac

  # Create installation directories.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  tmp_dir="$(mktemp -d)"
  if [ ! -d "${dst_dir}" ]; then
    ${super:+"${super}"} mkdir -p "${dst_dir}"
  fi

  log "Installing Deno to '${dst_file}'."
  fetch --dest "${tmp_dir}/deno.zip" \
    "https://dl.deno.land/release/${version}/deno-${target}.zip"
  unzip -d "${tmp_dir}" "${tmp_dir}/deno.zip"
  ${super:+"${super}"} mv "${tmp_dir}/deno" "${dst_file}"

  export PATH="${dst_dir}:${PATH}"
  log "Installed $(deno --version)."
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
        text="${1}"
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
# Script entrypoint.
#######################################
main() {
  local dst_dir='' global_='' super='' version=''

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -d | --dest)
        dst_dir="${2}"
        shift 2
        ;;
      -g | --global)
        dst_dir="${dst_dir:-/usr/local/bin}"
        global_='true'
        shift 1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -q | --quiet)
        export SCRIPTS_NOLOG='true'
        shift 1
        ;;
      -v | --version)
        version="${2}"
        shift 2
        ;;
      *)
        log --stderr "error: No such option '${1}'."
        log --stderr "Run 'install-deno --help' for usage."
        exit 2
        ;;
    esac
  done

  # Find super user command if destination is not writable.
  #
  # Flags:
  #   -w: Check if file exists and is writable.
  dst_dir="${dst_dir:-"${HOME}/.local/bin"}"
  if [ -n "${global_}" ] || ! mkdir -p "${dst_dir}" > /dev/null 2>&1 ||
    [ ! -w "${dst_dir}" ]; then
    super="$(find_super)"
  fi

  if [ -z "${version}" ]; then
    version="$(fetch 'https://dl.deno.land/release-latest.txt')"
  fi
  install_deno "${super}" "${version}" "${dst_dir}"
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
