#!/usr/bin/env sh
#
# Install Cargo for MacOS and Linux systems. This script differs from
# https://sh.rustup.rs by providing more installation options.

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
Installer script for Cargo.

Usage: install-cargo [OPTIONS]

Options:
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install Cargo
  -h, --help                Print help information
  -p, --preserve-env        Do not update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of Rust to install
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
# Download and install Cargo.
# Arguments:
#   Destination path.
#   Rust version (optional).
#   Whether to update system environment.
#######################################
install_cargo() {
  local dst_dir="${1}" version="${2:-}" preserve_env="${3}"
  local args='' bin_dir rustup_home
  bin_dir="${dst_dir}/bin"
  rustup_home="$(dirname "${dst_dir}")"

  # Determine RUSTUP_HOME based on destination directory name.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  local dest_name
  dest_name="$(basename "${dst_dir}")"
  case "${dest_name}" in
    .*)
      rustup_home="${rustup_home}/.rustup"
      ;;
    *)
      rustup_home="${rustup_home}/rustup"
      ;;
  esac

  # Build rustup installer arguments.
  #
  # Flags:
  #   -z: Check if string has zero length.
  args='-y --no-modify-path --profile minimal'
  if [ -n "${preserve_env:-}" ] || [ -n "${SCRIPTS_NOLOG:-}" ]; then
    args="${args} --quiet"
  fi
  if [ -n "${version:-}" ]; then
    args="${args} --default-toolchain ${version}"
  fi

  # Create installation directory.
  #
  # Flags:
  #   -p: Make parent directories if necessary.
  mkdir -p "${dst_dir}"

  log "Installing Cargo to '${bin_dir}/cargo'."
  # Do not quote args variable. Otherwise it will be interpreted as a single
  # argument.
  # shellcheck disable=SC2086
  fetch 'https://sh.rustup.rs' | env CARGO_HOME="${dst_dir}" \
    RUSTUP_HOME="${rustup_home}" PATH="${bin_dir}:${PATH}" sh -s -- ${args}

  # Update shell profile if destination is not in system path.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${preserve_env}" ]; then
    case ":${PATH:-}:" in
      *:${bin_dir}:*) ;;
      *)
        configure_shell "${bin_dir}"
        ;;
    esac
  fi

  export PATH="${bin_dir}:${PATH}"
  log "Installed $(cargo --version)."
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
# Check if super user elevation is required.
# Arguments:
#   Destination directory.
# Outputs:
#   0 if elevation is required, 1 otherwise.
#######################################
need_super() {
  local dest="${1}"
  if ! mkdir -p "${dest}" 2> /dev/null; then
    return 0
  fi
  if ! touch "${dest}/.super_check" 2> /dev/null; then
    rm -f "${dest}/.super_check"
    return 0
  fi
  rm -f "${dest}/.super_check"
  return 1
}

#######################################
# Script entrypoint.
#######################################
main() {
  local dst_dir='' preserve_env='' version=''

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
        log --stderr "Run 'install-cargo --help' for usage."
        exit 2
        ;;
    esac
  done

  # Choose destination if not selected.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${dst_dir}" ]; then
    dst_dir="${HOME}/.cargo"
  fi

  # Check if admin permissions are required since rustup cannot be installed
  # globally.
  #
  # Flags:
  #   -v: Only show file path of command.
  if [ "$(id -u)" -eq 0 ] || need_super "${dst_dir}"; then
    log --stderr 'error: Cargo cannot be installed with admin permissions.'
    exit 1
  fi
  install_cargo "${dst_dir}" "${version}" "${preserve_env}"
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
