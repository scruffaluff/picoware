#!/usr/bin/env sh
#
# Install scripts for FreeBSD, MacOS, and Linux systems.

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
Installer script for Scripts.

Usage: install-scripts [OPTIONS] [SCRIPTS]...

Options:
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install scripts
  -g, --global              Install scripts for all users
  -h, --help                Print help information
  -l, --list                List all available scripts
  -m, --modify-env          Update system environment
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of scripts to install
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
  log 'Source shell profile or restart shell after installation.'
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
# Find all scripts inside GitHub repository.
# Arguments:
#   Scripts version.
# Returns:
#   Array of script names.
#######################################
find_scripts() {
  local version="${1:-main}"
  local filter='.tree[] | select(.type == "blob") | .path | select(startswith("src/script/")) | select(endswith(".nu") or endswith(".sh")) | ltrimstr("src/script/")'
  local jq_bin='' response=''

  jq_bin="$(find_jq)"
  response="$(fetch "https://api.github.com/repos/scruffaluff/scripts/git/trees/${version}?recursive=true")"
  echo "${response}" | "${jq_bin}" --exit-status --raw-output "${filter}"

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
# Download and install script.
# Arguments:
#   Super user command for installation.
#   Script version.
#   Destination path.
#   Script file name.
#   Whether to update system environment.
#######################################
install_script() {
  local super="${1}" version="${2}" dst_dir="${3}" script="${4}"
  local modify_env="${5}" name="${4%.*}"
  local dst_file="${dst_dir}/${name}"
  local repo="https://raw.githubusercontent.com/scruffaluff/scripts/${version}/src"

  if [ "${script##*.}" = 'nu' ] && [ ! -x "$(command -v nu)" ]; then
    fetch https://scruffaluff.github.io/scripts/install/nushell.sh | sh -s -- \
      ${super:+--global} ${modify_env:+--modify-env} --quiet
  fi

  # Create installation directory.
  #
  # Flags:
  #   -p: Make parent directories if necessary.
  ${super:+"${super}"} mkdir -p "${dst_dir}"

  log "Installing script ${name} to '${dst_file}'."
  fetch --dest "${dst_file}" --mode 755 --super "${super}" \
    "${repo}/script/${script}"

  # Update shell profile if destination is not in system path.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  if [ -n "${modify_env}" ]; then
    case ":${PATH:-}:" in
      *:${dst_dir}:*) ;;
      *)
        configure_shell "${dst_dir}"
        ;;
    esac
  fi

  export PATH="${dst_dir}:${PATH}"
  log "Installed $("${name}" --version)."
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
  local dst_dir='' global_='' modify_env='' names='' super='' version='main'

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
      -l | --list)
        list_scripts='true'
        shift 1
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
        if [ -n "${names}" ]; then
          names="${names} ${1}"
        else
          names="${1}"
        fi
        shift 1
        ;;
    esac
  done

  scripts="$(find_scripts "${version}")"

  # Flags:
  #   -n: Check if string has nonzero length.
  #   -z: Check if string has zero length.
  if [ -n "${list_scripts:-}" ]; then
    for script in ${scripts}; do
      echo "${script%.*}"
    done
    return
  fi

  # Find super user command if destination is not writable.
  #
  # Flags:
  #   -p: Make parent directories if necessary.
  #   -w: Check if file exists and is writable.
  dst_dir="${dst_dir:-"${HOME}/.local/bin"}"
  if [ -n "${global_}" ] || ! mkdir -p "${dst_dir}" > /dev/null 2>&1 ||
    [ ! -w "${dst_dir}" ]; then
    super="$(find_super)"
  fi

  for name in ${names}; do
    match_found=''
    for script in ${scripts}; do
      if [ "${script%.*}" = "${name}" ]; then
        match_found='true'
        install_script "${super}" "${version}" "${dst_dir}" "${script}" \
          "${modify_env}"
      fi
    done

    if [ -z "${match_found:-}" ]; then
      log --stderr "error: No script found for '${names}'."
    fi
  done
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
