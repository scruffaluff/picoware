#!/usr/bin/env bats
#
# Tests for POSIX installer scripts.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
}

jq_install() { # @test
  run src/install/jq.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed jq-1.'
}

jq_install_quiet() { # @test
  run src/install/jq.sh --quiet --dest "$(mktemp -d)"
  assert_success
  assert_output ''
}

just_error_usage() { # @test
  run src/install/just.sh --dst
  assert_failure
  assert_output "$(
    cat << EOF
error: No such option '--dst'.
Run 'install-just --help' for usage.
EOF
  )"
}

just_install() { # @test
  run src/install/just.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed just 1.'
}

just_install_jq_download() { # @test
  # Ensure that local Jq binary is not found.
  # shellcheck disable=SC2317
  command() {
    if [ "${2}" = 'jq' ]; then
      echo ''
    else
      which "${2}"
    fi
  }
  export -f command

  run src/install/just.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed just 1.'
}

nushell_install() { # @test
  run src/install/nushell.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed Nushell 0.'
}
