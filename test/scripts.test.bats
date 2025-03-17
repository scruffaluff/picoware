#!/usr/bin/env bats
# shellcheck disable=SC2155,SC2317
#
# Tests for scripts installer.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-file/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
  bats_require_minimum_version 1.5.0

  command() {
    which "${2}"
  }
  curl() {
    if [ "$*" = '--fail --location --show-error --silent --output - https://api.github.com/repos/scruffaluff/scripts/git/trees/main?recursive=true' ]; then
      cat data/test/github_trees.json
    else
      "${_curl}" "$@"
    fi
  }
  _curl="$(command -v curl)"
}

json_parser_finds_all_unix_scripts() { # @test
  export _curl
  export -f command curl

  run src/install/scripts.sh --list
  assert_success
  assert_output $'mockscript\nnewscript\notherscript'
}

installer_uses_sudo_when_destination_is_not_writable() { # @test
  sudo() {
    if [ "$*" = 'mkdir -p /fake/path' ]; then
      exit 100
    else
      "${_sudo}" "$@"
    fi
  }
  export _curl _sudo="$(command -v sudo)"
  export -f command curl sudo

  run src/install/scripts.sh --debug --dest /fake/path mockscript
  assert_failure 100
}
