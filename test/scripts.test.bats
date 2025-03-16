#!/usr/bin/env bats
# shellcheck disable=SC2317
#
# Tests for scripts installer.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-file/load"
  load "${REPO_PATH}/.vendor/lib/bats-mock/stub"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
  bats_require_minimum_version 1.5.0

  stub command '-v curl : echo /usr/bin/env' '-v sudo : echo /usr/bin/env'
  stub curl '--fail --location --show-error --silent --output - https://api.github.com/repos/scruffaluff/scripts/git/trees/main?recursive=true : cat data/test/install_response.json'
}

json_parser_finds_all_posix_scripts() { # @test
  run src/install/scripts.sh --list
  assert_success
  assert_output $'mockscript\notherscript'
}

installer_uses_sudo_when_destination_is_not_writable() { # @test
  stub sudo 'mkdir -p /fake/path : exit 100'
  run src/install/scripts.sh --dest /fake/path mockscript
  assert_failure 100
}
