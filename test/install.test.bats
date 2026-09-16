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
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/deno.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_success
  assert_output --partial 'Installed deno 2.'
  rm -fr "${dst_dir}"
}

deno_shows_error_if_zip_missing() { # @test
  # Ensure that local unzip binary is not found.
  command() {
    if [ "$*" = '-v unzip' ]; then
      return 1
    else
      type -p "${2}"
    fi
  }
  export -f command

  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/deno.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_failure
  assert_output "$(
    cat << EOF
error: Unable to find zip file archiver.
Install zip, https://en.wikipedia.org/wiki/ZIP_(file_format), manually before continuing.
EOF
  )"
  rm -fr "${dst_dir}"
}

jq_prints_version() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/jq.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_success
  assert_output --partial 'Installed jq-1.'
  rm -fr "${dst_dir}"
}

jq_global_owner_is_root() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/jq.sh ${DEBUG:+--debug} --preserve-env --quiet --global \
    --dest "${dst_dir}"
  assert_success
  assert_file_owner root "${dst_dir}/jq"
  rm -fr "${dst_dir}"
}

jq_quiet_is_silent() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/jq.sh ${DEBUG:+--debug} --preserve-env --quiet --dest \
    "${dst_dir}"
  assert_success
  assert_output ''
  rm -fr "${dst_dir}"
}

just_shows_error_usage_for_bad_argument() { # @test
  run bash src/install/just.sh ${DEBUG:+--debug} --preserve-env --dst
  assert_failure
  assert_output "$(
    cat << EOF
error: No such option '--dst'.
Run 'install-just --help' for usage.
EOF
  )"
}

just_prints_version() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/just.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_success
  assert_output --partial 'Installed just 1.'
  rm -fr "${dst_dir}"
}

just_downloads_jq_if_missing() { # @test
  # Ensure that local jq binary is not found.
  command() {
    if [ "$*" = '-v jq' ]; then
      return 1
    else
      type -p "${2}"
    fi
  }
  export -f command

  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/just.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_success
  assert_output --partial 'Installed just 1.'
  rm -fr "${dst_dir}"
}

nushell_prints_version() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/nushell.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_success
  assert_output --partial 'Installed Nushell 0.'
  rm -fr "${dst_dir}"
}

nushell_shows_error_if_tar_missing() { # @test
  # Ensure that local tar binary is not found.
  command() {
    if [ "$*" = '-v tar' ]; then
      return 1
    else
      type -p "${2}"
    fi
  }
  export -f command

  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/nushell.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_failure
  assert_output "$(
    cat << EOF
error: Unable to find tar file archiver.
Install tar, https://gnu.org/software/tar, manually before continuing.
EOF
  )"
  rm -fr "${dst_dir}"
}

rust_script_prints_version() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/rust-script.sh ${DEBUG:+--debug} --preserve-env \
    --dest "${dst_dir}"
  assert_success
  assert_output --partial 'Installed rust-script 0.'
  rm -fr "${dst_dir}"
}

uv_prints_version() { # @test
  local dst_dir
  dst_dir="$(mktemp -d)"

  run bash src/install/uv.sh ${DEBUG:+--debug} --preserve-env --dest \
    "${dst_dir}"
  assert_success
  assert_output --partial 'Installed uv 0.'
  rm -fr "${dst_dir}"
}
