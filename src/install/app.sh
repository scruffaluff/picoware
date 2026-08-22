#!/usr/bin/env sh
#
# Installs Picoware apps for Unix systems.

# Exit immediately if a command exits with non-zero return code.
#
# Flags:
#   -e: Exit immediately when a command pipeline fails.
#   -u: Throw an error when an unset variable is encountered.
set -eu

#######################################
# Show CLI help information.
# Outputs:
#   Writes help information to standard output.
#######################################
usage() {
  cat 1>&2 << EOF
Installer script for Picoware apps.

Usage: install-apps [OPTIONS] <APPS>...

Options:
      --debug               Show shell debug traces
  -g, --global              Install apps for all users
  -h, --help                Print help information
  -l, --list                List all available apps
  -q, --quiet               Print only error messages
  -v, --version <VERSION>   Version of apps to install
EOF
}

#######################################
# Capitalize app name.
# Arguments:
#   Application name.
# Outputs:
#   Application desktop name.
#######################################
capitalize() {
  case "$(uname -s)" in
    Darwin)
      # MacOS specific case is necessary since builtin sed does not support
      # changing character case. AWK solution taken from
      # https://stackoverflow.com/a/31972726.
      echo "${1}" | sed 's/_/ /g' | awk '{for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1'
      ;;
    *)
      echo "${1}" | sed 's/_/ /g;s/[^ ]*/\u&/g'
      ;;
  esac
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

  # Create profile parent directory and add export command to profile.
  #
  # Flags:
  #   -p: Make parent directories if necessary.
  mkdir -p "$(dirname "${profile}")"
  printf '\n# Added by Picoware installer.\n%s\n' "${export_cmd}" >> "${profile}"
  log "Added '${export_cmd}' to the '${profile}' shell profile."
  log 'Source shell profile or restart shell after installation.'
}

#######################################
# Create application entrypoint script.
# Arguments:
#   Super user command for installation.
#   Application script name.
#   Runner folder path.
#   Entrypoint file path.
#######################################
create_entry() {
  local folder="${3}" script="${2}" super="${1}" path="${4}"
  local command='' shebang=''
  shebang="$(head -n 1 "$(dirname "${path}")/$(basename "${script}")")"
  command="$(echo "${shebang}" | sed 's/#!\/usr\/bin\/env -S //;s/#!\/usr\/bin\/env //')"

  cat << EOF | ${super:+"${super}"} tee "${path}" > /dev/null
#!/usr/bin/env sh
set -eu

# Add interpreter to system path.
export PATH="${folder}:\${PATH}"
# Resolve symlinks to find script folder.
folder="\$(dirname "\$(realpath "\${0}")")"
# Use interpeter to avoid env shebang conflicts.
exec ${command} "\${folder}/$(basename "${script}")" "\$@"
EOF
  ${super:+"${super}"} chmod +rx "${path}"
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
# Download application from repository.
# Arguments:
#   Super user command.
#   Picoware version.
#   App name.
#   Destination path.
#######################################
fetch_app() {
  local dest="${4}" name="${3}" super="${1}" version="${2}"
  local filter=".tree[] | select(.type == \"blob\") | .path | select(startswith(\"src/app/${name}\")) | ltrimstr(\"src/app/${name}/\")"
  local jq_bin='' response='' script=''
  local url="https://raw.githubusercontent.com/scruffaluff/picoware/refs/heads/${version}/src/app/${name}"

  jq_bin="$(find_jq)"
  response="$(fetch "https://api.github.com/repos/scruffaluff/picoware/git/trees/${version}?recursive=true")"
  files="$(echo "${response}" | "${jq_bin}" --exit-status --raw-output "${filter}")"

  ${super:+"${super}"} mkdir -p "${dest}"
  for file in ${files}; do
    case "${file##*.}" in
      nu | py | rs | sh | ts)
        if [ "${file%.*}" = 'main' ]; then
          script="${dest}/${file}"
        fi
        fetch --dest "${dest}/${file}" --mode 755 --super "${super}" \
          "${url}/${file}"
        ;;
      *)
        fetch --dest "${dest}/${file}" --super "${super}" "${url}/${file}"
        ;;
    esac
  done

  if [ -z "${script}" ]; then
    log --stderr "error: No entry point found in app ${name}."
    exit 1
  fi
  echo "${script}"
}

#######################################
# Find all apps inside repository.
# Arguments:
#   Picoware version.
# Outputs:
#   Array of app names.
#######################################
find_apps() {
  local version="${1:-main}"
  local filter='.tree[] | select(.type == "tree") | .path | select(startswith("src/app/")) | ltrimstr("src/app/")'
  local jq_bin='' response=''

  jq_bin="$(find_jq)"
  response="$(fetch "https://api.github.com/repos/scruffaluff/picoware/git/trees/${version}?recursive=true")"
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
    response="$(fetch 'https://scruffaluff.github.io/picoware/install/jq.sh')"
    tmp_dir="$(mktemp -d)"
    echo "${response}" | sh -s -- --preserve-env --quiet --dest "${tmp_dir}"
    echo "${tmp_dir}/jq"
  fi
}

#######################################
# Find application runner.
# Arguments:
#   Super user command.
#   Picoware filename.
# Outputs:
#   Application runner path.
#######################################
find_runner() {
  # System path is temporarily updated to ensure that runners can be found.
  local script="${2}" super="${1}"
  local runner=''
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

  if [ "${script##*.}" = 'nu' ]; then
    if ! command -v nu > /dev/null 2>&1; then
      fetch https://scruffaluff.github.io/picoware/install/nushell.sh | sh -s \
        -- ${super:+--global} --preserve-env --quiet
    fi
    runner="$(command -v nu)"
  elif [ "${script##*.}" = 'py' ]; then
    if ! command -v uv > /dev/null 2>&1; then
      fetch https://scruffaluff.github.io/picoware/install/uv.sh | sh -s -- \
        ${super:+--global} --preserve-env --quiet
    fi
    runner="$(command -v uv)"
  elif [ "${script##*.}" = 'rs' ]; then
    if ! command -v rust-script > /dev/null 2>&1; then
      fetch https://scruffaluff.github.io/picoware/install/rust-script.sh | sh \
        -s -- ${super:+--global} --preserve-env --quiet
    fi
    runner="$(command -v rust-script)"
  elif [ "${script##*.}" = 'ts' ]; then
    if ! command -v deno > /dev/null 2>&1; then
      fetch https://scruffaluff.github.io/picoware/install/deno.sh | sh -s -- \
        ${super:+--global} --preserve-env --quiet
    fi
    runner="$(command -v deno)"
  else
    log --stderr "error: Unable to find an application runner for ${script}."
    exit 1
  fi

  echo "${runner}"
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
# Install application.
# Arguments:
#   Super user command for installation.
#   Whether to perform system installation.
#   Repository version branch.
#   App name.
#######################################
install_app() {
  local global_="${2}" name="${4}" super="${1}" version="${3}"
  local installer='' os='' runner='' script='' title='' tmp_dir=''

  # Do not use long form flags for uname. They are not supported on some
  # systems.
  #
  # Flags:
  #   -s: Show operating system kernel name.
  os="$(uname -s)"
  title="$(capitalize "${name}")"
  case "${os}" in
    Darwin)
      installer='install_app_macos'
      ;;
    Linux)
      installer='install_app_linux'
      ;;
    *)
      log --stderr "error: Operating system ${os} is not supported"
      exit 1
      ;;
  esac

  log "Installing application ${title}."
  tmp_dir="$(mktemp -d)"
  script="$(fetch_app "${super}" "${version}" "${name}" "${tmp_dir}")"
  runner="$(find_runner "${super}" "${script}")"

  "${installer}" "${super}" "${global_}" "${version}" "${name}" "${tmp_dir}" \
    "${script}" "${runner}"
}

#######################################
# Install application for Linux.
# Arguments:
#   Super user command for installation.
#   Whether to perform system installation.
#   Repository version branch.
#   App name.
#   Download folder.
#   Application script name.
#   Application runner path.
#######################################
install_app_linux() {
  local dest='' global_="${2}" name="${4}" runner="${7}" script="${6}" \
    src="${5}" super="${1}" version="${3}"
  local title=''
  local url="https://raw.githubusercontent.com/scruffaluff/picoware/refs/heads/${version}"
  local icon_url="${url}/data/image/icon.svg"
  title="$(capitalize "${name}")"

  if [ -n "${global_}" ]; then
    cli_dir="/usr/local/bin"
    dest="/usr/local/app/${name}"
    manifest="/usr/local/share/applications/${name}.desktop"
  else
    cli_dir="${HOME}/.local/bin"
    dest="${HOME}/.local/app/${name}"
    manifest="${HOME}/.local/share/applications/${name}.desktop"
  fi
  entry_point="${dest}/main.sh"
  icon="${dest}/icon.svg"

  if [ ! -f "${src}/icon.svg" ]; then
    fetch --dest "${src}/icon.svg" "${icon_url}"
  fi
  find . -delete -name "icon.*" -not -name "icon.svg"
  create_entry "" "${script}" "$(dirname "${runner}")" "${src}/main.sh"

  ${super:+"${super}"} mkdir -p "$(dirname "${dest}")"
  ${super:+"${super}"} cp "${src}" "${dest}"
  ${super:+"${super}"} ln -fs "${entry_point}" "${cli_dir}/${name}"
  rm -fr "${src}"

  # Parse window class to ensure correct dock icon.
  case "$(basename "${runner}")" in
    deno)
      wmclass='GTK Application'
      ;;
    rust-script)
      wmclass='GTK Application'
      ;;
    uv)
      wmclass='python3'
      ;;
    *)
      wmclass=''
      ;;
  esac

  cat << EOF | ${super:+"${super}"} tee "${manifest}" > /dev/null
[Desktop Entry]
Exec=${entry_point}
Icon=${icon}
Name=${title}
StartupWMClass=${wmclass}
Terminal=false
Type=Application
EOF
  ${super:+"${super}"} update-desktop-database "$(dirname "${manifest}")"

  # Update shell profile if CLI is not in system path.
  case ":${PATH:-}:" in
    *:${cli_dir}:*) ;;
    *)
      configure_shell "${cli_dir}"
      ;;
  esac

  export PATH="${cli_dir}:${PATH}"
  log "Installed $("${name}" --version)."
}

#######################################
# Install application for MacOS.
# Arguments:
#   Super user command for installation.
#   Whether to perform system installation.
#   Repository version branch.
#   App name.
#   Download folder.
#   Application script name.
#   Application runner path.
#######################################
install_app_macos() {
  local dest='' global_="${2}" name="${4}" runner="${7}" script="${6}" \
    src="${5}" super="${1}" version="${3}"
  local bundle='' identifier='' title=''
  local url="https://raw.githubusercontent.com/scruffaluff/picoware/refs/heads/${version}"
  local icon_url="${url}/data/image/icon.icns"
  identifier="com.scruffaluff.app-$(echo "${name}" | sed 's/_/-/g')"
  title="$(capitalize "${name}")"

  if [ -n "${global_}" ]; then
    bundle="/Applications/${title}.app/Contents"
    cli_dir="/usr/local/bin"
  else
    bundle="${HOME}/Applications/${title}.app/Contents"
    cli_dir="${HOME}/.local/bin"
  fi
  dest="${bundle}/MacOS"

  if [ ! -f "${src}/icon.icns" ]; then
    fetch --dest "${icon}" "${src}/icon.icns"
  fi
  create_entry "" "${script}" "$(dirname "${runner}")" "${src}/main.sh"

  ${super:+"${super}"} mkdir -p "$(dirname "${dest}")" "${bundle}/Resources"
  ${super:+"${super}"} cp -r "${src}/icon.icns" "${bundle}/Resources/icon.icns"
  rm "${src}"/icon.*
  ${super:+"${super}"} cp -r "${src}" "${dest}"
  ${super:+"${super}"} ln -fs "${dest}/main.sh" "${cli_dir}/${name}"
  rm -fr "${src}"

  cat << EOF | ${super:+"${super}"} tee "${bundle}/Info.plist" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleDisplayName</key>
  <string>${title}</string>
  <key>CFBundleExecutable</key>
  <string>main.sh</string>
  <key>CFBundleIconFile</key>
  <string>icon.icns</string>
  <key>CFBundleIdentifier</key>
  <string>${identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${name}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CSResourcesFileMapped</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>10.13</string>
  <key>LSRequiresCarbon</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

  # Update shell profile if CLI is not in system path.
  case ":${PATH:-}:" in
    *:${cli_dir}:*) ;;
    *)
      configure_shell "${cli_dir}"
      ;;
  esac

  export PATH="${cli_dir}:${PATH}"
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
  local global_='' list_apps='' names='' super='' version='main'

  # Parse command line arguments.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -g | --global)
        global_='true'
        shift 1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -l | --list)
        list_apps='true'
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

  if [ -n "${list_apps:-}" ]; then
    apps="$(find_apps "${version}")"
    for app in ${apps}; do
      echo "${app%.*}"
    done
    return
  elif [ -n "${names}" ]; then
    apps="$(find_apps "${version}")"

    # Find super user command if global installation.
    if [ -n "${global_}" ]; then
      super="$(find_super)"
    elif [ "$(id -u)" -eq 0 ]; then
      global_='true'
    fi

    for name in ${names}; do
      match_found=''
      for app in ${apps}; do
        if [ "${app%.*}" = "${name}" ]; then
          match_found='true'
          install_app "${super}" "${global_}" "${version}" "${app}"
        fi
      done

      if [ -z "${match_found:-}" ]; then
        log --stderr "error: No app found for '${name}'."
      fi
    done
  else
    log --stderr 'error: App argument required.'
    log --stderr "Run 'install-apps --help' for usage."
    exit 2
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
