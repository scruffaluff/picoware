#!/usr/bin/env bats
# shellcheck disable=SC2317
#
# Tests for scripts installer.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-file/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"

  command() {
    which "${2}"
  }
  curl() {
    cat data/test/install_response.json
  }
}

json_parser_finds_all_posix_scripts() { # @test
  export -f command
  export -f curl

  run src/install/scripts.sh --list
  assert_success
  assert_output $'mockscript\notherscript'
}

installer_uses_sudo_when_destination_is_not_writable() { # @test
  sudo() {
    echo "sudo $*"
    exit 0
  }
  export -f command curl sudo

  run src/install/scripts.sh --quiet --dest /fake/path mockscript
  assert_success
  assert_output 'sudo mkdir -p /fake/path'
}
