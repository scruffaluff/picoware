#!/usr/bin/env sh
#
# Install Scripts apps for MacOS and Linux systems.

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
Installer script for Scripts application.

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
      echo "${1}" | sed 's/_/ /g' | sed 's/[^ ]*/\u&/g'
      ;;
  esac
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
  command="$(echo "${shebang}" | sed 's/#!\/usr\/bin\/env -S //;#!\/usr\/bin\/env //')"

  cat << EOF | ${super:+"${super}"} tee "${path}" > /dev/null
#!/usr/bin/env sh
set -eu

# Add interpreter to system path.
export PATH="${folder}:\${PATH}"
# Resolve symlinks to find script folder.
folder="\$(dirname "\$(readlink "\${0}")")"
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
# Download application from repository.
# Arguments:
#   Super user command.
#   Scripts version.
#   App name.
#   Destination path.
#######################################
fetch_app() {
  local dest="${4}" name="${3}" super="${1}" version="${2}"
  local filter=".tree[] | select(.type == \"blob\") | .path | select(startswith(\"src/app/${name}\")) | ltrimstr(\"src/app/${name}/\")"
  local jq_bin='' response='' script=''
  local url="https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/${version}/src/app/${name}"

  jq_bin="$(find_jq)"
  response="$(fetch "https://api.github.com/repos/scruffaluff/scripts/git/trees/${version}?recursive=true")"
  files="$(echo "${response}" | "${jq_bin}" --exit-status --raw-output "${filter}")"

  ${super:+"${super}"} mkdir -p "${dest}"
  for file in ${files}; do
    case "${file##*.}" in
      py | rs | ts)
        if [ "${file%.*}" = 'index' ]; then
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

  echo "${script}"
}

#######################################
# Find all apps inside repository.
# Arguments:
#   Scripts version.
# Outputs:
#   Array of app names.
#######################################
find_apps() {
  local version="${1:-main}"
  local filter='.tree[] | select(.type == "tree") | .path | select(startswith("src/app/")) | ltrimstr("src/app/")'
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
# Find application runner.
# Arguments:
#   Super user command.
#   Scripts filename.
# Outputs:
#   Application runner path.
#######################################
find_runner() {
  local script="${2}" super="${1}"
  local runner=''

  if [ "${script##*.}" = 'nu' ]; then
    runner="$(command -v nu)"
    if [ ! -x "${runner}" ]; then
      fetch https://scruffaluff.github.io/scripts/install/nushell.sh | sh -s \
        -- ${super:+--global} --preserve-env --quiet
      runner="$(command -v nu)"
    fi
  elif [ "${script##*.}" = 'py' ]; then
    runner="$(command -v uv)"
    if [ ! -x "${runner}" ]; then
      fetch https://scruffaluff.github.io/scripts/install/uv.sh | sh -s -- \
        ${super:+--global} --preserve-env --quiet
      runner="$(command -v uv)"
    fi
  elif [ "${script##*.}" = 'ts' ]; then
    runner="$(command -v deno)"
    if [ ! -x "${runner}" ]; then
      fetch https://scruffaluff.github.io/scripts/install/deno.sh | sh -s -- \
        ${super:+--global} --preserve-env --quiet
      runner="$(command -v deno)"
    fi
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
# Install application for Linux.
# Arguments:
#   Super user command for installation.
#   Repository version branch.
#   App name.
#######################################
install_app_linux() {
  local name="${3}" super="${1}" version="${2}"
  local runner='' script='' title=''
  local url="https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/${version}"
  local icon_url="${url}/data/image/icon.svg"
  title="$(capitalize "${name}")"

  if [ -n "${super}" ]; then
    cli_dir="/usr/local/bin"
    dest="/usr/local/app/${name}"
    manifest="/usr/local/share/applications/${name}.desktop"
  else
    cli_dir="${HOME}/.local/bin"
    dest="${HOME}/.local/app/${name}"
    manifest="${HOME}/.local/share/applications/${name}.desktop"
  fi
  entry_point="${dest}/index.sh"
  icon="${dest}/icon.svg"

  log "Installing application ${title}."
  fetch --dest "${icon}" --super "${super}" "${icon_url}"
  script="$(fetch_app "${super}" "${version}" "${name}" "${dest}")"
  runner="$(find_runner "${super}" "${script}")"
  create_entry "${super}" "${script}" "$(dirname "${runner}")" "${entry_point}"
  ${super:+"${super}"} ln -fs "${entry_point}" "${cli_dir}/${name}"

  # Parse window class to ensure correct dock icon.
  case "$(basename "${runner}")" in
    deno)
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
  export PATH="${cli_dir}:${PATH}"
  log "Installed $("${name}" --version)."
}

#######################################
# Install application for MacOS.
# Arguments:
#   Super user command for installation.
#   Repository version branch.
#   App name.
#######################################
install_app_macos() {
  local name="${3}" super="${1}" version="${2}"
  local identifier='' title=''
  local url="https://raw.githubusercontent.com/scruffaluff/scripts/refs/heads/${version}"
  local icon_url="${url}/data/image/icon.icns"
  identifier="com.scruffaluff.app-$(echo "${name}" | sed 's/_/-/g')"
  title="$(capitalize "${name}")"

  if [ -n "${super}" ]; then
    cli_dir="/usr/local/bin"
    dest="/Applications/${title}.app/Contents/MacOS"
    icon="/Applications/${title}.app/Contents/Resources/icon.icns"
    manifest="/Applications/${title}.app/Contents/Info.plist"
  else
    cli_dir="${HOME}/.local/bin"
    dest="${HOME}/Applications/${title}.app/Contents/MacOS"
    icon="${HOME}/Applications/${title}.app/Contents/Resources/icon.icns"
    manifest="${HOME}/Applications/${title}.app/Contents/Info.plist"
  fi
  entry_point="${dest}/index.sh"

  log "Installing application ${title}."
  fetch --dest "${icon}" --super "${super}" "${icon_url}"
  script="$(fetch_app "${super}" "${2}" "${name}" "${dest}")"
  runner="$(find_runner "${super}" "${script}")"
  create_entry "${super}" "${script}" "$(dirname "${runner}")" "${entry_point}"
  ${super:+"${super}"} ln -fs "${entry_point}" "${cli_dir}/${name}"

  cat << EOF | ${super:+"${super}"} tee "${manifest}" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleDisplayName</key>
  <string>${title}</string>
  <key>CFBundleExecutable</key>
  <string>index.sh</string>
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
  local global_='' names='' super='' version='main'

  # Parse command line arguments.
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

  apps="$(find_apps "${version}")"

  # Flags:
  #   -n: Check if string has nonzero length.
  #   -z: Check if string has zero length.
  if [ -n "${list_apps:-}" ]; then
    for app in ${apps}; do
      echo "${app%.*}"
    done
    return
  fi
  if [ -n "${global_}" ]; then
    super="$(find_super)"
  elif [ "$(id -u)" -eq 0 ]; then
    global_='true'
  fi

  # Do not use long form flags for uname. They are not supported on some
  # systems.
  os="$(uname -s)"
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

  for name in ${names}; do
    match_found=''
    for app in ${apps}; do
      if [ "${app%.*}" = "${name}" ]; then
        match_found='true'
        "${installer}" "${super}" "${version}" "${app}"
      fi
    done

    if [ -z "${match_found:-}" ]; then
      log --stderr "error: No app found for '${names}'."
    fi
  done
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
