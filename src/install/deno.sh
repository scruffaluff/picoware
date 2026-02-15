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
  -p, --preserve-env        Do not update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Deno to install
EOF
}

#######################################
# Add script to system path in shell profile.
# Arguments:
#   Parent directory of Picoware script.
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
  printf '\n# Added by Picoware installer.\n%s\n' "${export_cmd}" >> "${profile}"
  log "Added '${export_cmd}' to the '${profile}' shell profile."
  log 'Source shell profile or restart shell after installation.'
}

#######################################
# Perform network request.
#######################################
fetch() {
  local dst_file='-' mode='' super='' url=''

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
    ${super:+"${super}"} mkdir -p "$(dirname "${dst_file}")"
  fi

  # Download with Curl or Wget.
  #
  # Flags:
  #   -O <PATH>: Save download to path.
  #   -q: Hide log output.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if command -v curl > /dev/null 2>&1; then
    ${super:+"${super}"} curl --fail --location --show-error --silent --output \
      "${dst_file}" "${url}"
  elif command -v wget > /dev/null 2>&1; then
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
# Download and install Deno.
# Arguments:
#   Super user command for installation.
#   Deno version.
#   Destination path.
#   Whether to update system environment.
#######################################
install_deno() {
  local super="${1}" version="${2}" dst_dir="${3}" preserve_env="${4}"
  local arch='' dst_file="${dst_dir}/deno" os='' target='' tmp_dir=''

  # Parse Deno build target.
  #
  # Do not use long form flags for uname. They are not supported on some
  # systems.
  #
  # Flags:
  #   -m: Show system architecture name.
  #   -s: Show operating system kernel name.
  arch="$(uname -m | sed 's/amd64/x86_64/;s/x64/x86_64/;s/arm64/aarch64/')"
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

  # Exit early if tar is not installed.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if ! command -v unzip > /dev/null 2>&1; then
    log --stderr 'error: Unable to find zip file archiver.'
    log --stderr 'Install zip, https://en.wikipedia.org/wiki/ZIP_(file_format), manually before continuing.'
    exit 1
  fi

  # Create installation directories.
  #
  # Flags:
  #   -p: Make parent directories if necessary.
  tmp_dir="$(mktemp -d)"
  ${super:+"${super}"} mkdir -p "${dst_dir}"

  log "Installing Deno to '${dst_file}'."
  fetch --dest "${tmp_dir}/deno.zip" \
    "https://dl.deno.land/release/${version}/deno-${target}.zip"
  unzip -d "${tmp_dir}" "${tmp_dir}/deno.zip"
  ${super:+"${super}"} install "${tmp_dir}/deno" "${dst_file}"

  # Update shell profile if destination is not in system path.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${preserve_env}" ]; then
    case ":${PATH:-}:" in
      *:${dst_dir}:*) ;;
      *)
        configure_shell "${dst_dir}"
        ;;
    esac
  fi

  export PATH="${dst_dir}:${PATH}"
  log "Installed $(deno -V)."
}

#######################################
# Download and install Deno for Alpine.
#######################################
install_deno_alpine() {
  local super
  super="$(find_super)"

  log 'Alpine Deno installation requires system package manager.'
  log "Ignoring arguments and installing Deno to '/usr/bin/deno'."
  ${super:+"${super}"} apk update
  ${super:+"${super}"} apk add deno
  log "Installed $(deno -V)."
}

#######################################
# Download and install Deno for FreeBSD.
#######################################
install_deno_freebsd() {
  local super
  super="$(find_super)"

  log 'FreeBSD Deno installation requires system package manager.'
  log "Ignoring arguments and installing Deno to '/usr/local/bin/deno'."
  ${super:+"${super}"} pkg update
  ${super:+"${super}"} pkg install --yes deno
  log "Installed $(deno -V)."
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
# Script entrypoint.
#######################################
main() {
  local dst_dir='' global_='' preserve_env='' super='' version=''

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
        return
        ;;
      -p | --preserve-env)
        preserve_env='true'
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
        log --stderr "Run 'install-deno --help' for usage."
        exit 2
        ;;
    esac
  done

  # Handle special installation cases.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if command -v apk > /dev/null 2>&1; then
    install_deno_alpine
    return
  elif [ "$(uname -s)" = 'FreeBSD' ]; then
    install_deno_freebsd
    return
  fi

  # Choose destination if not selected.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${dst_dir}" ]; then
    if [ "$(id -u)" -eq 0 ]; then
      global_='true'
      dst_dir='/usr/local/bin'
    else
      dst_dir="${HOME}/.local/bin"
    fi
  fi

  # Find super user command if destination is not writable.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  #   -p: Make parent directories if necessary.
  #   -w: Check if file exists and is writable.
  if [ -n "${global_}" ] || ! mkdir -p "${dst_dir}" > /dev/null 2>&1 ||
    [ ! -w "${dst_dir}" ]; then
    global_='true'
    super="$(find_super)"
  fi

  if [ -z "${version}" ]; then
    version="$(fetch 'https://dl.deno.land/release-latest.txt')"
  fi
  install_deno "${super}" "${version}" "${dst_dir}" "${preserve_env}"
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
