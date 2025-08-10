#!/usr/bin/env bats
# shellcheck disable=SC2317,SC2329
#
# Tests for Bash installer scripts.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-file/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
  bats_require_minimum_version 1.5.0
}

deno_prints_version() { # @test
  run bash src/install/deno.sh --preserve-env --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed deno 2.'
}

deno_shows_error_if_zip_missing() { # @test
  # Ensure that local unzip binary is not found.
  command() {
    if [ "$*" = '-v unzip' ]; then
      echo ""
    else
      which "${2}"
    fi
  }
  export -f command

  run bash src/install/deno.sh --preserve-env --dest "$(mktemp -d)"
  assert_failure
  assert_output "$(
    cat << EOF
error: Unable to find zip file archiver.
Install zip, https://en.wikipedia.org/wiki/ZIP_(file_format), manually before continuing.
EOF
  )"
}

jq_prints_version() { # @test
  run bash src/install/jq.sh --preserve-env --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed jq-1.'
}

jq_global_owner_is_root() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/jq.sh --preserve-env --quiet --global --dest "${dst_dir}"
  assert_success
  assert_file_owner root "${dst_dir}/jq"
}

jq_quiet_is_silent() { # @test
  run bash src/install/jq.sh --preserve-env --quiet --dest "$(mktemp -d)"
  assert_success
  assert_output ''
}

just_shows_error_usage_for_bad_argument() { # @test
  run bash src/install/just.sh --preserve-env --dst
  assert_failure
  assert_output "$(
    cat << EOF
error: No such option '--dst'.
Run 'install-just --help' for usage.
EOF
  )"
}

just_prints_version() { # @test
  run bash src/install/just.sh --preserve-env --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed just 1.'
}

just_downloads_jq_if_missing() { # @test
  # Ensure that local jq binary is not found.
  command() {
    if [ "$*" = '-v jq' ]; then
      echo ""
    else
      which "${2}"
    fi
  }
  export -f command

  run bash src/install/just.sh --preserve-env --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed just 1.'
}

nushell_prints_version() { # @test
  run bash src/install/nushell.sh --preserve-env --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed Nushell 0.'
}

nushell_shows_error_if_tar_missing() { # @test
  # Ensure that local tar binary is not found.
  command() {
    if [ "$*" = '-v tar' ]; then
      echo ""
    else
      which "${2}"
    fi
  }
  export -f command

  run bash src/install/nushell.sh --preserve-env --dest "$(mktemp -d)"
  assert_failure
  assert_output "$(
    cat << EOF
error: Unable to find tar file archiver.
Install tar, https://www.gnu.org/software/tar, manually before continuing.
EOF
  )"
}

uv_prints_version() { # @test
  run bash src/install/uv.sh --preserve-env --dest "$(mktemp -d)"
  assert_success
  assert_output --partial 'Installed uv 0.'
}
