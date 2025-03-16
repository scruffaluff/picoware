#!/usr/bin/env sh
#
# Install scripts for FreeBSD, MacOS, or Linux systems.

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

Usage: install [OPTIONS] [SCRIPTS]...

Options:
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install scripts
  -g, --global              Install scripts for all users
  -h, --help                Print help information
  -l, --list                List all available scripts
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of scripts to install
EOF
}

#######################################
# Add Scripts to system path in user's shell profile.
# Globals:
#   HOME
#   PATH
#   SHELL
# Arguments:
#   Parent directory of Scripts script.
#######################################
configure_shell() {
  export_cmd="export PATH=\"${1}:\$PATH\""
  shell_name="$(basename "${SHELL}")"

  case "${shell_name}" in
    bash)
      profile="${HOME}/.bashrc"
      ;;
    fish)
      export_cmd="set -x PATH \"${1}\" \$PATH"
      profile="${HOME}/.config/fish/config.fish"
      ;;
    nu)
      export_cmd="\$env.PATH = [\"${1}\" ...\$env.PATH]"
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

  printf '\n# Added by Scripts installer.\n%s\n' "${export_cmd}" \
    >> "${profile}"
  log "Added '${export_cmd}' to the '${profile}' shell profile."
  log 'Source the profile or restart the shell after installation.'
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
  # Create parent directory if it does not exist.
  #
  # Flags:
  #   -d: Check if path exists and is a directory.
  folder="$(dirname "${3}")"
  if [ ! -d "${folder}" ]; then
    ${1:+"${1}"} mkdir -p "${folder}"
  fi

  # Download with Curl or Wget.
  #
  # Flags:
  #   -O path: Save download to path.
  #   -q: Hide log output.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v curl)" ]; then
    ${1:+"${1}"} curl --fail --location --show-error --silent --output "${3}" \
      "${2}"
  elif [ -x "$(command -v wget)" ]; then
    ${1:+"${1}"} wget -q -O "${3}" "${2}"
  else
    error "$(
      cat << EOF
Unable to find a network file downloader.
Install curl, https://curl.se, manually before continuing.
EOF
    )"
  fi

  # Change file permissions if chmod parameter was passed.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  if [ -n "${4:-}" ]; then
    ${1:+"${1}"} chmod "${4}" "${3}"
  fi
}

#######################################
# Download Jq binary to temporary path.
# Arguments:
#   Operating system name.
# Outputs:
#   Path to temporary Jq binary.
#######################################
download_jq() {
  # Do not use long form --machine flag for uname. It is not supported on MacOS.
  #
  # Flags:
  #   -m: Show system architecture name.
  arch="$(uname -m | sed s/x86_64/amd64/ | sed s/x64/amd64/ |
    sed s/aarch64/arm64/)"
  tmp_path="$(mktemp)"
  download '' \
    "https://github.com/jqlang/jq/releases/latest/download/jq-${1}-${arch}" \
    "${tmp_path}" 755
  echo "${tmp_path}"
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
  printf "Run 'install --help' for usage.\n" >&2
  exit 2
}

#######################################
# Find or download Jq JSON parser.
# Outputs:
#   Path to Jq binary.
#######################################
find_jq() {
  # Do not use long form --kernel-name flag for uname. It is not supported on
  # MacOS.
  #
  # Flags:
  #   -s: Show operating system kernel name.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  jq_bin="$(command -v jq || echo '')"
  if [ -x "${jq_bin}" ]; then
    echo "${jq_bin}"
  else
    case "$(uname -s)" in
      Darwin)
        download_jq macos
        ;;
      FreeBSD)
        super="$(find_super)"
        ${super:+"${super}"} pkg update > /dev/null 2>&1
        ${super:+"${super}"} pkg install --yes jq > /dev/null 2>&1
        command -v jq
        ;;
      Linux)
        download_jq linux
        ;;
      *)
        error "$(
          cat << EOF
Cannot find required 'jq' command on computer.
Please install 'jq' and retry installation.
EOF
        )"
        ;;
    esac
  fi
}

#######################################
# Find all scripts inside GitHub repository.
# Arguments:
#   Version
# Returns:
#   Array of script names.
#######################################
find_scripts() {
  url="https://api.github.com/repos/scruffaluff/scripts/git/trees/${1}?recursive=true"

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
    error "$(
      cat << EOF
Unable to find a network file downloader.
Install curl, https://curl.se, manually before continuing.
EOF
    )"
  fi

  jq_bin="$(find_jq)"
  filter='.tree[] | select(.type == "blob") | .path | select(startswith("src/script/")) | select(endswith(".nu") or endswith(".sh")) | ltrimstr("src/script/")'
  echo "${response}" | "${jq_bin}" --exit-status --raw-output "${filter}"
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
# Install script and update path.
# Arguments:
#   Super user command for installation
#   Script URL prefix
#   Destination path prefix
#   Script name
# Globals:
#   SCRIPTS_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
install_script() {
  local super="${1}" dst_dir="${3}" name="${4%.*}"
  local dst_file="${dst_dir}/${name}"
  local repo="https://raw.githubusercontent.com/scruffaluff/scripts/${2}"
  local src_url="${repo}/src/script/${4}"

  if [ "${4##*.}" = 'nu' ] && [ ! -x "$(command -v nu)" ]; then
    if [ -z "${1}" ]; then
      curl -LSfs "${repo}/src/install/nushell.sh" | sh
    else
      curl -LSfs "${repo}/src/install/nushell.sh" | sh -s -- --user
    fi
  fi

  log "Installing script ${name} to '${dst_file}'."
  download "${super}" "${src_url}" "${dst_file}" 755

  # Add Scripts to shell profile if not in system path.
  #
  # Flags:
  #   -e: Check if file exists.
  #   -v: Only show file path of command.
  if [ ! -e "$(command -v "${name}")" ]; then
    configure_shell "${dst_dir}"
    export PATH="${dst_dir}:${PATH}"
  fi

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
        text="${1}"
        shift 1
        ;;
    esac
  done

  # Print if error or using quiet configuration.
  #
  # Flags:
  #   -z: Check if string has nonzero length.
  if [ -z "${SCRIPTS_NOLOG:-}" ] || [ "${file}" = '2' ]; then
    printf "%s${newline}" "${text}" >&"${file}"
  fi
}

#######################################
# Script entrypoint.
#######################################
main() {
  dst_dir='' names='' super='' version='main'

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
        dst_dir="${dst_dir:-'/usr/local/bin'}"
        super="$(find_super)"
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

  dst_dir="${dst_dir:-"${HOME}/.local/bin"}"
  scripts="$(find_scripts "${version}")"

  # Flags:
  #   -n: Check if string has nonzero length.
  #   -z: Check if string has zero length.
  if [ -n "${list_scripts:-}" ]; then
    for script in ${scripts}; do
      echo "${script%.*}"
    done
  else
    for name in ${names}; do
      match_found=''
      for script in ${scripts}; do
        if [ "${script%.*}" = "${name}" ]; then
          match_found='true'
          install_script "${super}" "${version}" "${dst_dir}" "${script}"
        fi
      done

      if [ -z "${match_found:-}" ]; then
        error_usage "No script found for '${names}'."
      fi
    done
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
