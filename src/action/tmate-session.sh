#!/usr/bin/env sh
#
# Installs Tmate and creates a session suitable for CI pipelines. Based on logic
# from https://github.com/mxschmitt/action-tmate.

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
Installs Tmate and creates a remote session.

Users can close the session by creating the file /close-tmate.

Usage: run-tmate [OPTIONS]

Options:
      --debug     Show shell debug traces
  -h, --help      Print help information
  -v, --version   Print version information
EOF
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
# Install Tmate.
# Arguments:
#   Super user command for installation.
#######################################
install_tmate() {
  # Do not use long form --kernel-name flag for uname. It is not supported on
  # MacOS.
  os="$(uname -s)"
  case "${os}" in
    Darwin)
      # Setting environment variable 'HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK'
      # prevents upgrading outdated system packages during a Homebrew
      # installation of a new package. This is necessary since in some systems,
      # such as GitLab CI, upgrading system packages causes breakage.
      HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK='true' brew install tmate
      ;;
    FreeBSD)
      ${1:+"${1}"} pkg update
      ${1:+"${1}"} pkg install --yes tmate
      ;;
    Linux)
      install_tmate_linux "${1}"
      ;;
    *)
      log --stderr "error: Operating system ${os} is not supported."
      exit 1
      ;;
  esac
}

#######################################
# Install Tmate for Linux.
# Arguments:
#   Super user command for installation.
#######################################
install_tmate_linux() {
  tmate_version='2.4.0'

  # Short form machine flag '-m' should be used since processor flag and long
  # form machine flag '--machine' are non-portable. For more information, visit
  # https://www.gnu.org/software/coreutils/manual/html_node/uname-invocation.html#index-_002dp-12.
  arch="$(uname -m)"
  case "${arch}" in
    x86_64 | amd64)
      tmate_arch='amd64'
      ;;
    arm64 | aarch64)
      tmate_arch='arm64v8'
      ;;
    *)
      log --stderr "error: Unsupported architecture ${arch}."
      exit 1
      ;;
  esac

  # Install OpenSSH and archive utils if not available.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ ! -x "$(command -v curl)" ] || [ ! -x "$(command -v ssh)" ] ||
    [ ! -x "$(command -v tar)" ] || [ ! -x "$(command -v xz)" ]; then
    if [ -x "$(command -v apk)" ]; then
      ${1:+"${1}"} apk add curl openssh-client tar xz
    elif [ -x "$(command -v apt-get)" ]; then
      ${1:+"${1}"} apt-get update
      ${1:+"${1}"} apt-get install --yes curl openssh-client tar xz-utils
    elif [ -x "$(command -v dnf)" ]; then
      ${1:+"${1}"} dnf install --assumeyes curl openssh tar xz
    elif [ -x "$(command -v pacman)" ]; then
      ${1:+"${1}"} pacman --noconfirm --refresh --sync --sysupgrade
      ${1:+"${1}"} pacman --noconfirm --sync curl openssh tar xz
    elif [ -x "$(command -v zypper)" ]; then
      ${1:+"${1}"} zypper install --no-confirm curl openssh tar xz
    fi
  fi

  curl --fail --location --show-error --silent --output /tmp/tmate.tar.xz \
    "https://github.com/tmate-io/tmate/releases/download/${tmate_version}/tmate-${tmate_version}-static-linux-${tmate_arch}.tar.xz"
  tar xvf /tmp/tmate.tar.xz --directory /tmp --strip-components 1
  ${1:+"${1}"} install /tmp/tmate /usr/local/bin/tmate
  rm /tmp/tmate /tmp/tmate.tar.xz
}

#######################################
# Installs Tmate and creates a remote session.
#######################################
setup_tmate() {
  super="$(find_super)"

  # Install Tmate if not available.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ ! -x "$(command -v tmate)" ]; then
    install_tmate "${super}"
  fi

  # Launch new Tmate session with custom socket.
  #
  # Flags:
  #   -S: Set Tmate socket path.
  tmate -S /tmp/tmate.sock new-session -d
  tmate -S /tmp/tmate.sock wait tmate-ready
  ssh_connect="$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')"
  web_connect="$(tmate -S /tmp/tmate.sock display -p '#{tmate_web}')"

  while true; do
    echo "SSH: ${ssh_connect}"
    echo "Web shell: ${web_connect}"

    # Check if script should exit.
    #
    # Flags:
    #   -S: Check if file exists and is a socket.
    #   -f: Check if file exists and is a regular file.
    if [ ! -S /tmp/tmate.sock ] || [ -f /close-tmate ] || [ -f ./close-tmate ]; then
      break
    fi

    sleep 5
  done
}

#######################################
# Print Setup Tmate version string.
# Outputs:
#   Setup Tmate version string.
#######################################
version() {
  echo 'SetupTmate 0.4.0'
}

#######################################
# Script entrypoint.
#######################################
main() {
  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -v | --version)
        version
        exit 0
        ;;
      *)
        log --stderr "error: No such option '${1}'."
        log --stderr "Run 'tmate-session --help' for usage."
        exit 2
        ;;
    esac
  done

  setup_tmate
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
