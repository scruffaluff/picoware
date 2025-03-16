#!/usr/bin/env bats
#
# Tests for POSIX installer scripts.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
}

jq_install_succeeds() { # @test
  run src/install/jq.sh --dest "$(mktemp -d)"
  assert_output --partial 'Installed jq-1.'
}

just_install_succeeds() { # @test
  run src/install/just.sh --dest "$(mktemp -d)"
  assert_output --partial 'Installed just 1.'
}

nushell_install_succeeds() { # @test
  run src/install/nushell.sh --dest "$(mktemp -d)"
  assert_output --partial 'Installed Nushell 0.'
}
