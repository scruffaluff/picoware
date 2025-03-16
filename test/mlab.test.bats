#!/usr/bin/env bats

setup() {
  REPO_PATH="${BATS_TEST_DIRNAME}/.."
  cd "${REPO_PATH}" || exit
  load "${REPO_PATH}/.vendor/lib/bats-assert/load"
  load "${REPO_PATH}/.vendor/lib/bats-file/load"
  load "${REPO_PATH}/.vendor/lib/bats-support/load"
  bats_require_minimum_version 1.5.0

  export MLAB_PROGRAM='/bin/matlab'
  export SCRIPTS_NOLOG='true'
}

argumentless_call_contains_no_commands() { # @test
  local actual expected
  expected='/bin/matlab -nodisplay -nosplash'

  actual="$(bash src/script/mlab.sh run --echo)"
  assert_equal "${actual}" "${expected}"
}

debug_call_contains_sets_breakpoint_on_error() { # @test
  local actual expected
  expected='/bin/matlab -nodisplay -nosplash -r dbstop if error;'

  actual="$(bash src/script/mlab.sh run --echo --debug)"
  assert_equal "${actual}" "${expected}"
}

function_call_contains_one_batch_command() { # @test
  local actual expected
  expected='/bin/matlab -nodesktop -nosplash -batch script'

  actual="$(bash src/script/mlab.sh run --echo script)"
  assert_equal "${actual}" "${expected}"
}

genpath_option_call_contains_multiple_path_commands() { # @test
  local actual expected
  expected="/bin/matlab -nodisplay -nosplash -r addpath(genpath('/tmp')); "

  actual="$(bash src/script/mlab.sh run --echo --genpath /tmp)"
  assert_equal "${actual}" "${expected}"
}

path_option_call_contains_path_command() { # @test
  local actual expected
  expected="/bin/matlab -nodisplay -nosplash -r addpath('/tmp'); "

  actual="$(bash src/script/mlab.sh run --echo --addpath /tmp)"
  assert_equal "${actual}" "${expected}"
}

script_call_contains_one_batch_command() { # @test
  local actual expected
  expected="/bin/matlab -nodesktop -nosplash -batch addpath('src'); script"

  actual="$(bash src/script/mlab.sh run --echo src/script.m)"
  assert_equal "${actual}" "${expected}"
}

debug_script_call_contains_several_commands() { # @test
  local actual expected
  expected="/bin/matlab -nodisplay -nosplash -r addpath('src'); dbstop if \
error; dbstop in script; script; exit"

  actual="$(bash src/script/mlab.sh run --echo --debug src/script.m)"
  assert_equal "${actual}" "${expected}"
}
