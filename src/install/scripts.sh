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

Usage: install-scripts [OPTIONS] <SCRIPTS>...

Options:
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install scripts
  -g, --global              Install scripts for all users
  -h, --help                Print help information
  -l, --list                List all available scripts
  -p, --preserve-env        Do not update system environment
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
# Find all installable completions inside repository.
# Arguments:
#   Scripts version.
# Outputs:
#   Array of completion names.
#######################################
find_completions() {
  local version="${1:-main}"
  local filter='.tree[] | select(.type == "blob") | .path | select(startswith("src/completion/")) | select(endswith(".bash") or endswith(".fish") or endswith(".nu")) | ltrimstr("src/completion/")'
  local jq_bin='' response=''

  jq_bin="$(find_jq)"
  response="$(fetch "https://api.github.com/repos/scruffaluff/scripts/git/trees/${version}?recursive=true")"
  echo "${response}" | "${jq_bin}" --exit-status --raw-output "${filter}"
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
# Find all installable scripts inside repository.
# Arguments:
#   Scripts version.
# Outputs:
#   Array of script names.
#######################################
find_scripts() {
  local version="${1:-main}"
  local filter='.tree[] | select(.type == "blob") | .path | select(startswith("src/script/")) | select(endswith(".nu") or endswith(".py") or endswith(".sh") or endswith(".ts")) | ltrimstr("src/script/")'
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
# Create entrypoint script if necessary.
# Arguments:
#   Super user command for installation.
#   Script file path.
#   Original extension for script.
#######################################
handle_shebang() {
  local extension="${3}" path="${2}" super="${1}"
  local command='' script="${path}.${extension}" shebang=''
  shebang="$(head -n 1 "${path}")"

  # Exit early if `env` can handle the shebang arguments.
  case "${shebang}" in
    '#!/usr/bin/env -S'*)
      if env -S echo test > /dev/null 2>&1; then
        return
      fi
      ;;
    *)
      return
      ;;
  esac

  # Move script to new location.
  command="$(echo "${shebang}" | sed 's/#!\/usr\/bin\/env -S //')"
  ${super:+"${super}"} cp "${path}" "${script}"
  ${super:+"${super}"} chmod -x "${script}"

  # Add entrypoint replacement for script.
  cat << EOF | ${super:+"${super}"} tee "${path}" > /dev/null
#!/usr/bin/env sh
set -eu

exec ${command} '${script}' "\$@"
EOF
  ${super:+"${super}"} chmod +rx "${path}"
}

#######################################
# Install completion scripts.
# Arguments:
#   Super user command for installation.
#   Whether installation is global.
#   Script version.
#   Script file name.
#######################################
install_completion() {
  local super="${1}" global_="${2}" version="${3}" script="${4}"
  local completions='' dest='' extension='' name="${script%.*}"
  local repo="https://raw.githubusercontent.com/scruffaluff/scripts/${version}/src/completion"

  # Find completions matching script name.
  #
  # Since grep exits with error is no matches are found, and empty or statement
  # is required.
  completions="$(find_completions "${version}" | { grep "${name}." || :; })"

  for completion in ${completions}; do
    extension="${completion##*.}"
    case "${extension}" in
      fish)
        dest="$(path_fish_completion "${global_}" "${name}")"
        ;;
      *)
        log --stderr "error: ${extension} shell completion is not supported."
        exit 1
        ;;
    esac

    fetch --dest "${dest}" --super "${super}" "${repo}/${completion}"
  done
}

#######################################
# Download and install script.
# Arguments:
#   Super user command for installation.
#   Whether installation is global.
#   Script version.
#   Destination path.
#   Script file name.
#   Whether to update system environment.
#######################################
install_script() {
  local super="${1}" global_="${2}" version="${3}" dst_dir="${4}" script="${5}"
  local preserve_env="${6}" extension="${script##*.}" name="${script%.*}"
  local dst_file="${dst_dir}/${name}"
  local repo="https://raw.githubusercontent.com/scruffaluff/scripts/${version}/src"

  if [ "${extension}" = 'nu' ] && [ ! -x "$(command -v nu)" ]; then
    fetch https://scruffaluff.github.io/scripts/install/nushell.sh | sh -s -- \
      ${global_:+--global} ${preserve_env:+--preserve-env} --quiet
  elif [ "${extension}" = 'py' ] && [ ! -x "$(command -v uv)" ]; then
    fetch https://scruffaluff.github.io/scripts/install/uv.sh | sh -s -- \
      ${global_:+--global} ${preserve_env:+--preserve-env} --quiet
  elif [ "${extension}" = 'ts' ] && [ ! -x "$(command -v deno)" ]; then
    fetch https://scruffaluff.github.io/scripts/install/deno.sh | sh -s -- \
      ${global_:+--global} ${preserve_env:+--preserve-env} --quiet
  fi

  log "Installing script ${name} to '${dst_file}'."
  fetch --dest "${dst_file}" --mode 755 --super "${super}" \
    "${repo}/script/${script}"
  install_completion "${super}" "${global_}" "${version}" "${script}"
  handle_shebang "${super}" "${dst_file}" "${extension}"

  # Update shell profile if destination is not in system path.
  #
  # Flags:
  #   -n: Check if string has zero length.
  if [ -z "${preserve_env}" ]; then
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
# Parse Fish completion path.
# Arguments:
#   Whether installation is global.
#   Script file name.
#######################################
path_fish_completion() {
  local global_="${1}" name="${2}"
  local os
  os="$(uname -s)"

  if [ -n "${global_}" ]; then
    case "${os}" in
      Darwin)
        dest="/etc/fish/completions/${name}.fish"
        ;;
      FreeBSD)
        dest="/usr/local/etc/fish/completions/${name}.fish"
        ;;
      Linux)
        dest="/etc/fish/completions/${name}.fish"
        ;;
      *)
        log --stderr "error: Operating system ${os} is not supported."
        exit 1
        ;;
    esac
  else
    dest="${HOME}/.config/fish/completions/${name}.fish"
  fi

  echo "${dest}"
}

#######################################
# Script entrypoint.
#######################################
main() {
  local dst_dir='' global_='' preserve_env='' names='' super='' version='main'

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
      -l | --list)
        list_scripts='true'
        shift 1
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
        if [ -n "${names}" ]; then
          names="${names} ${1}"
        else
          names="${1}"
        fi
        shift 1
        ;;
    esac
  done

  # Flags:
  #   -n: Check if string has nonzero length.
  if [ -n "${list_scripts:-}" ]; then
    scripts="$(find_scripts "${version}")"
    for script in ${scripts}; do
      echo "${script%.*}"
    done
    return
  elif [ -n "${names}" ]; then
    scripts="$(find_scripts "${version}")"

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

    for name in ${names}; do
      match_found=''
      for script in ${scripts}; do
        if [ "${script%.*}" = "${name}" ]; then
          match_found='true'
          install_script "${super}" "${global_}" "${version}" "${dst_dir}" \
            "${script}" "${preserve_env}"
        fi
      done

      if [ -z "${match_found:-}" ]; then
        log --stderr "error: No script found for '${name}'."
      fi
    done
  else
    log --stderr 'error: Script argument required.'
    log --stderr "Run 'install-scripts --help' for usage."
    exit 2
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
