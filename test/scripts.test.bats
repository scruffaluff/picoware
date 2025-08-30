#!/usr/bin/env bats
# shellcheck disable=SC2317,SC2329
#
# Tests for Bash scripts installer.

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-file/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
  bats_require_minimum_version 1.5.0

  # TODO: Figure out why command needs to be mocked.
  command() {
    which "${2}"
  }
  curl() {
    case "$*" in
      *?recursive=true)
        cat data/test/github_trees.json
        ;;
      *)
        "${_curl}" "$@"
        ;;
    esac
  }
  _curl="$(type -p curl)"
}

create_wrapper_for_incompatible_env() { # @test
  local temp
  temp="$(mktemp -d)"

  curl() {
    case "$*" in
      *?recursive=true)
        cat data/test/github_trees.json
        ;;
      *src/script/pyscript.py)
        cp data/test/pyscript.py "${_temp}/pyscript"
        ;;
      *)
        "${_curl}" "$@"
        ;;
    esac
  }
  env() {
    return 100
  }
  export _curl _temp="${temp}"
  export -f command curl env

  run bash src/install/scripts.sh --preserve-env --dest "${temp}" pyscript
  assert_success
  assert_equal "$(ls -1 "${temp}")" $'pyscript\npyscript.py'
  assert_equal "$(head -n 1 "${temp}/pyscript")" "#!/usr/bin/env sh"
  assert_equal "$(head -n 1 "${temp}/pyscript.py")" \
    "#!/usr/bin/env -S uv --no-config --quiet run --script"
}

json_parser_finds_all_unix_scripts() { # @test
  export _curl
  export -f command curl

  run bash src/install/scripts.sh --list
  assert_success
  assert_output $'mockscript\nnewscript\notherscript\npyscript'
}

installer_uses_sudo_when_destination_is_not_writable() { # @test
  sudo() {
    if [ "$*" = 'mkdir -p /fake/path' ]; then
      exit 100
    else
      "${_sudo}" "$@"
    fi
  }
  _sudo="$(type -p sudo)"
  export _curl _sudo
  export -f command curl sudo

  run bash src/install/scripts.sh --preserve-env --dest /fake/path mockscript
  assert_failure 100
}
