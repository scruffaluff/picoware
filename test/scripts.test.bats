#!/usr/bin/env bats

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"

  # Disable logging to simplify stdout for testing.
  export SCRIPTS_NOLOG='true'

  # Mock functions for child processes.
  #
  # Args:
  #   -f: Use override as a function instead of a variable.
  # shellcheck disable=SC2317
  command() {
    which jq
  }
  export -f command

  # shellcheck disable=SC2317
  curl() {
    if [[ "$*" =~ api\.github\.com ]]; then
      cat test/data/install_response.json
    else
      echo "curl $*"
      exit 0
    fi
  }
  export -f curl
}

installer_passes_local_path_to_curl() { # @test
  local actual expected
  expected="curl --fail --location --show-error --silent --output \
${HOME}/.local/bin/otherscript \
https://raw.githubusercontent.com/scruffaluff/scripts/develop/src/script/otherscript.sh"

  actual="$(bash src/install/scripts.sh --user --version develop otherscript)"
  assert_equal "${actual}" "${expected}"
}

json_parser_finds_all_posix_scripts() { # @test
  local actual expected
  expected=$'mockscript\notherscript'

  actual="$(bash src/install/scripts.sh --list)"
  assert_equal "${actual}" "${expected}"
}

installer_uses_sudo_when_destination_is_not_writable() { # @test
  local actual expected

  # Mock functions for child processes by printing received arguments.
  #
  # Args:
  #   -f: Use override as a function instead of a variable.
  # shellcheck disable=SC2317
  sudo() {
    echo "sudo $*"
    exit 0
  }
  export -f sudo

  expected='sudo mkdir -p /bin/fake'
  actual="$(bash src/install/scripts.sh --dest /bin/fake mockscript)"
  assert_equal "${actual}" "${expected}"
}
