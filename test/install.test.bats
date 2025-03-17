#!/usr/bin/env bats
# shellcheck disable=SC2317
#
# Tests for POSIX installer scripts.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-file/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
  bats_require_minimum_version 1.5.0
}

jq_install_prints_version() { # @test
  run src/install/jq.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed jq-1.'
}

jq_install_global_owner_is_root() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run src/install/jq.sh --quiet --global --dest "${dst_dir}"
  assert_success
  assert_file_owner root "${dst_dir}/jq"
}

jq_install_quiet_is_silent() { # @test
  run src/install/jq.sh --quiet --dest "$(mktemp -d)"
  assert_success
  assert_output ''
}

just_install_shows_error_usage_for_bad_argument() { # @test
  run src/install/just.sh --dst
  assert_failure
  assert_output "$(
    cat << EOF
error: No such option '--dst'.
Run 'install-just --help' for usage.
EOF
  )"
}

just_install_prints_version() { # @test
  run src/install/just.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed just 1.'
}

just_install_downloads_jq_if_missing() { # @test
  # Ensure that local Jq binary is not found.
  command() {
    if [ "$*" = '-v jq' ]; then
      echo ""
    else
      which "${2}"
    fi
  }
  export -f command

  run src/install/just.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed just 1.'
}

nushell_install_prints_version() { # @test
  run src/install/nushell.sh --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed Nushell 0.'
}

nushell_install_shows_error_if_tar_missing() { # @test
  # Ensure that local Tar binary is not found.
  command() {
    if [ "$*" = '-v tar' ]; then
      echo ""
    else
      which "${2}"
    fi
  }
  export -f command

  run src/install/nushell.sh --dest "$(mktemp -d)"
  assert_failure
  assert_output "$(
    cat << EOF
error: Unable to find tar file archiver.
Install tar, https://www.gnu.org/software/tar, manually before continuing.
EOF
  )"
}
