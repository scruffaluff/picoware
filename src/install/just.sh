#!/usr/bin/env sh
#
# Install Just for MacOS and Linux systems. This script differs from
# https://just.systems/install.sh by using the Homebrew API to avoid GitHub API
# rate limits.

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
Installer script for Just.

Usage: install-just [OPTIONS]

Options:
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install Just
  -h, --help                Print help information
  -u, --user                Install Just for current user
  -v, --version <VERSION>   Version of Just to install
EOF
}

#######################################
# Download file to local path.
# Arguments:
#   Super user command for installation.
#   Remote source URL.
#   Local destination path.
#   Optional permissions for file.
#######################################
download() {
  local super="${1}" url="${2}" dst_file="${3}" mode="${4:-}"
  local dst_dir=''

  # Create parent directory if it does not exist.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  dst_dir="$(dirname "${dst_file}")"
  if [ ! -d "${dst_dir}" ]; then
    ${super:+"${super}"} mkdir -p "${dst_dir}"
  fi

  # Download with Curl or Wget.
  #
  # Flags:
  #   -O path: Save download to path.
  #   -q: Hide log output.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v curl)" ]; then
    ${super:+"${super}"} curl --fail --location --show-error --silent --output \
      "${dst_file}" "${url}"
  elif [ -x "$(command -v wget)" ]; then
    ${super:+"${super}"} wget -q -O "${dst_file}" "${url}"
  else
    log --stderr 'Unable to find a network file downloader.'
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
# Find or download Jq JSON parser.
# Outputs:
#   Path to Jq binary.
#######################################
find_jq() {
  local jq_bin=''

  # Do not use long form flags for uname. They are not supported on some
  # systems.
  #
  # Flags:
  #   -s: Show operating system kernel name.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  jq_bin="$(command -v jq || echo '')"
  if [ -x "${jq_bin}" ]; then
    echo "${jq_bin}"
  else
    tmp_dir="$(mktemp -d)"
    SCRIPTS_NOLOG='true' curl -LSfs \
      https://scruffaluff.github.io/scripts/install/jq/sh | sh -s -- --dest \
      "${tmp_dir}"
    echo "${tmp_dir}/jq"
  fi
}

#######################################
# Find latest Just version.
#######################################
find_latest() {
  local response='' url='https://formulae.brew.sh/api/formula/just.json'

  # Flags:
  #   -O path: Save download to path.
  #   -q: Hide log output.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v curl)" ]; then
    response="$(curl --fail --location --show-error --silent "${url}")"
  elif [ -x "$(command -v wget)" ]; then
    response="$(wget -q -O - "${url}")"
  else
    log --stderr 'error: Unable to find a network file downloader.'
    log --stderr 'Install curl, https://curl.se, manually before continuing.'
    exit 1
  fi

  jq_bin="$(find_jq)"
  printf "%s" "${response}" | "${jq_bin}" --exit-status --raw-output \
    '.versions.stable'
}

#######################################
# Find command to elevate as super user.
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
# Download Just binary to temporary path.
# Arguments:
#   Operating system name.
# Outputs:
#   Path to temporary Just binary.
#######################################
install_just() {
  local user="${1}" version="${2}" dst_dir="${3}"
  local arch='' dst_file="${dst_dir}/just" os='' target='' tmp_dir=''

  # Parse Just build target.
  #
  # Do not use long form flags for uname. They are not supported on some
  # systems.
  #
  # Flags:
  #   -m: Show system architecture name.
  #   -s: Show operating system kernel name.
  arch="$(uname -m | sed s/amd64/x86_64/ | sed s/x64/x86_64/ \
    | sed s/arm64/aarch64/)"
  os="$(uname -s)"
  case "${os}" in
    Darwin)
      target="${arch}-apple-darwin"
      ;;
    Linux)
      target="${arch}-unknown-linux-musl"
      ;;
    *)
      log --stderr "error: Unsupported operating system '${os}'."
      exit 1
      ;;
  esac

  # Get super user elevation command for system installation if necessary.
  if [ -z "${user}" ]; then
    super="$(find_super)"
  else
    super=''
  fi

  # Create installation directories.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  tmp_dir="$(mktemp -d)"
  if [ ! -d "${dst_dir}" ]; then
    ${super:+"${super}"} mkdir -p "${dst_dir}"
  fi

  log "Installing Just to '${dst_file}'."
  download "${super}" \
    "https://github.com/casey/just/releases/download/${version}/just-${version}-${target}.tar.gz" \
    "${tmp_dir}/just.tar.gz" 755
  tar fx "${tmp_dir}/just.tar.gz" -C "${tmp_dir}"
  ${super:+"${super}"} mv "${tmp_dir}/just" "${dst_file}"

  export PATH="${dst_dir}:${PATH}"
  log "Installed $(just --version)."
}

#######################################
# Print message if logging is enabled.
# Globals:
#   SCRIPTS_NOLOG
# Outputs:
#   Message.
#######################################
log() {
  local file='1' newline="\n" text=''

  # Exit early if environment variable is set.
  #
  # Flags:
  #   -z: Check if string has nonzero length.
  if [ -n "${SCRIPTS_NOLOG:-}" ]; then
    return
  fi

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
      ;;
  esac

  printf '%s%s' "${text}" "${newline}" >&"${file}"
}

#######################################
# Script entrypoint.
#######################################
main() {
  local dst_dir='/usr/local/bin' user='' version=''

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
      -h | --help)
        usage
        exit 0
        ;;
      -u | --user)
        dst_dir="${HOME}/.local/bin"
        user='true'
        shift 1
        ;;
      -v | --version)
        version="${2}"
        shift 2
        ;;
      *)
        log --stderr "error: No such option '${1}'."
        echo "Run 'install-just --help' for usage" >&2
        exit 2
        ;;
    esac
  done

  if [ -z "${version}" ]; then
    version="$(find_latest)"
  fi
  install_just "${user}" "${version}" "${dst_dir}"
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
