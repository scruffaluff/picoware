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
  -g, --global              Install Just for all users
  -h, --help                Print help information
  -m, --modify-env          Update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Just to install
EOF
}

#######################################
# Add script to system path in shell profile.
# Arguments:
#   Parent directory of Scripts script.
# Globals:
#   SHELL
#######################################
configure_shell() {
  local dst_dir="${1}"
  export_cmd="export PATH=\"${dst_dir}:\${PATH}\""
  shell_name="$(basename "${SHELL:-}")"

  case "${shell_name}" in
    bash)
      profile="${HOME}/.bashrc"
      ;;
    fish)
      export_cmd="set --export PATH \"${dst_dir}\" \$PATH"
      profile="${HOME}/.config/fish/config.fish"
      ;;
    nu)
      export_cmd="\$env.PATH = [\"${dst_dir}\" ...\$env.PATH]"
      if [ "$(uname -s)" = 'Darwin' ]; then
        profile="${HOME}/Library/Application Support/nushell/config.nu"
      else
        profile="${HOME}/.config/nushell/config.nu"
      fi
      ;;
    zsh)
      profile="${HOME}/.zshrc"
      ;;
    *)
      profile="${HOME}/.profile"
      ;;
  esac

  # Create profile parent directory and add export command to profile
  #
  # Flags:
  #   -p: Make parent directories if necessary.
  mkdir -p "$(dirname "${profile}")"
  printf '\n# Added by Scripts installer.\n%s\n' "${export_cmd}" >> "${profile}"
  log "Added '${export_cmd}' to the '${profile}' shell profile."
  log 'Source the profile or restart the shell to continue.'
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
  #   -p: Make parent directories if necessary.
  if [ "${dst_file}" != '-' ]; then
    ${super:+"${super}"} mkdir -p "$(dirname "${dst_dir}")"
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
# Find or download Jq JSON parser.
# Outputs:
#   Path to Jq binary.
#######################################
find_jq() {
  local jq_bin='' response='' tmp_dir=''

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
    response="$(fetch 'https://scruffaluff.github.io/scripts/install/jq.sh')"
    tmp_dir="$(mktemp -d)"
    echo "${response}" | sh -s -- --quiet --dest "${tmp_dir}"
    echo "${tmp_dir}/jq"
  fi
}

#######################################
# Find latest Just version.
#######################################
find_latest() {
  local jq_bin='' response=''
  jq_bin="$(find_jq)"
  response="$(fetch 'https://formulae.brew.sh/api/formula/just.json')"
  printf "%s" "${response}" | "${jq_bin}" --exit-status --raw-output \
    '.versions.stable'
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
# Download and install Just.
# Arguments:
#   Super user command for installation.
#   Just version.
#   Destination path.
#   Whether to update system path.
#######################################
install_just() {
  local super="${1}" version="${2}" dst_dir="${3}" modify_env="${4}"
  local arch='' dst_file="${dst_dir}/just" os='' target='' tmp_dir=''

  # Exit early if tar is not installed.
  #
  # Flags:
  #   -v: Only show file path of command.
  if [ ! -x "$(command -v tar)" ]; then
    log --stderr 'error: Unable to find tar file archiver.'
    log --stderr 'Install tar, https://www.gnu.org/software/tar, manually before continuing.'
    exit 1
  fi

  # Parse Just build target.
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
      target="${arch}-unknown-linux-musl"
      ;;
    *)
      log --stderr "error: Unsupported operating system '${os}'."
      exit 1
      ;;
  esac

  # Create installation directories.
  #
  # Flags:
  #   -p: Make parent directories if necessary.
  tmp_dir="$(mktemp -d)"
  ${super:+"${super}"} mkdir -p "${dst_dir}"

  log "Installing Just to '${dst_file}'."
  fetch --dest "${tmp_dir}/just.tar.gz" \
    "https://github.com/casey/just/releases/download/${version}/just-${version}-${target}.tar.gz"
  tar fx "${tmp_dir}/just.tar.gz" -C "${tmp_dir}"
  ${super:+"${super}"} mv "${tmp_dir}/just" "${dst_file}"

  # Update shell profile if destination is not in system path.
  #
  # Flags:
  #   -e: Check if file exists.
  #   -n: Check if string has nonzero length.
  #   -v: Only show file path of command.
  if [ -n "${modify_env}" ] && [ ! -e "$(command -v just)" ]; then
    configure_shell "${dst_dir}"
  fi

  export PATH="${dst_dir}:${PATH}"
  log "Installed $(just --version)."
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
  local dst_dir='' global_='' modify_env='' super='' version=''

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
      -m | --modify-env)
        modify_env='true'
        shift 1
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
        log --stderr "Run 'install-just --help' for usage."
        exit 2
        ;;
    esac
  done

  # Find super user command if destination is not writable.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  #   -p: Make parent directories if necessary.
  #   -w: Check if file exists and is writable.
  dst_dir="${dst_dir:-"${HOME}/.local/bin"}"
  if [ -n "${global_}" ] || ! mkdir -p "${dst_dir}" > /dev/null 2>&1 ||
    [ ! -w "${dst_dir}" ]; then
    super="$(find_super)"
  fi

  if [ -z "${version}" ]; then
    version="$(find_latest)"
  fi
  install_just "${super}" "${version}" "${dst_dir}" "${modify_env}"
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
