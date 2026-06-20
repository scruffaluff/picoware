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
  if [ -n "${DEBUG:-}" ]; then
    run bash src/install/apps.sh ${DEBUG:+--debug} --debug --list
  else
    run bash src/install/apps.sh ${DEBUG:+--debug} --list
  fi

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

# shellcheck disable=SC2016
create_entry_wraps_shebang() { # @test
  BATS_SOURCE_ONLY='true' source src/install/apps.sh
  local entry temp
  temp="$(mktemp -d)"
  entry="${temp}/main.sh"

  echo '#!/usr/bin/env nu' > "${temp}/main.nu"
  create_entry '' 'main.nu' '/usr/local/bin' "${entry}"

  run cat "${entry}"
  assert_line 'export PATH="/usr/local/bin:${PATH}"'
  assert_line 'exec '\''nu'\'' "${folder}/main.nu" "$@"'
}

json_parser_finds_all_apps() { # @test
  export _curl
  export -f curl

  run bash src/install/apps.sh ${DEBUG:+--debug} ${DEBUG:+--debug} --list
  assert_success
  assert_output $'pyapp\nrsapp'
}
