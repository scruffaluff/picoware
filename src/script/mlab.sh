#!/usr/bin/env sh
#
# Wrapper script for running Matlab programs from the command line.

# Exit immediately if a command exits with non-zero return code.
#
# Flags:
#   -e: Exit immediately when a command pipeline fails.
#   -u: Throw an error when an unset variable is encountered.
set -eu

#######################################
# Show CLI help information.
# Outputs:
#   Writes help information to stdout.
#######################################
usage() {
  case "${1}" in
    main)
      cat 1>&2 << EOF
Wrapper script for running Matlab programs from the command line.

Usage: mlab [OPTIONS] [SUBCOMMAND]

Options:
      --debug       Enable shell debug traces
  -h, --help        Print help information
  -v, --version     Print version information

Subcommands:
  jupyter   Launch Jupyter Lab with Matlab kernel
  run       Execute Matlab code
EOF
      ;;
    jupyter)
      cat 1>&2 << EOF
Launch Jupyter Lab with the Matlab kernel.

Usage: mlab jupyter [OPTIONS] [ARGS]...

Options:
  -h, --help        Print help information
EOF
      ;;
    run)
      cat 1>&2 << EOF
Execute Matlab code.

Usage: mlab run [OPTIONS] [SCRIPT] [ARGS]...

Options:
  -a, --addpath <PATH>        Add folder to Matlab path
  -b, --batch                 Use batch mode for session
  -c, --license <LOCATION>    Set location of Matlab license file
  -d, --debug                 Use Matlab debugger for session
  -e, --echo                  Print Matlab command and exit
  -h, --help                  Print help information
  -i, --interactive           Use interactive mode for session
  -l, --log <PATH>            Copy command window output to logfile
  -s, --sd <PATH>             Set the Matlab startup folder
EOF
      ;;
    *)
      error "No such usage option '${1}'"
      ;;
  esac
}

#######################################
# Print error message and exit script with error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error() {
  bold_red='\033[1;31m' default='\033[0m'
  # Flags:
  #   -t <FD>: Check if file descriptor is a terminal.
  if [ -t 2 ]; then
    printf "${bold_red}error${default}: %s\n" "${1}" >&2
  else
    printf "error: %s\n" "${1}" >&2
  fi
  exit 1
}

#######################################
# Print error message and exit script with usage error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error_usage() {
  bold_red='\033[1;31m' default='\033[0m'
  # Flags:
  #   -t <FD>: Check if file descriptor is a terminal.
  if [ -t 2 ]; then
    printf "${bold_red}error${default}: %s\n" "${1}" >&2
  else
    printf "error: %s\n" "${1}" >&2
  fi
  printf "Run 'mlab %s--help' for usage.\n" "${2:+${2} }" >&2
  exit 2
}

#######################################
# Find Matlab executable on system.
# Outputs:
#   Matlab executable path.
#######################################
find_matlab() {
  program=''

  # Search standard locations for first Matlab installation.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  #   -s: Show operating system kernel name.
  if [ -n "${MLAB_PROGRAM:-}" ]; then
    program="${MLAB_PROGRAM}"
  else
    case "$(uname -s)" in
      Darwin)
        for folder in /Applications/MATLAB_*.app; do
          program="${folder}/bin/matlab"
          break
        done
        ;;
      *)
        if [ -d '/usr/local/MATLAB' ]; then
          for folder in /usr/local/MATLAB/R*; do
            program="${folder}/bin/matlab"
            break
          done
        fi
        ;;
    esac
  fi

  # Throw error if Matlab was not found.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${program}" ]; then
    error 'Unable to find a Matlab installation'
  else
    echo "${program}"
  fi
}

#######################################
# Convert Matlab script into a module call.
# Outputs:
#   Module path.
#######################################
get_module() {
  case "${1}" in
    *.m)
      basename "${1}" .m
      ;;
    *)
      echo "${1}"
      ;;
  esac
}

#######################################
# Launch Jupyter Lab with the Matlab kernel.
#######################################
jupyter() {
  share_dir="${HOME}/.local/share/mlab"

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      -h | --help)
        usage 'run'
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done

  matlab_dir="$(dirname "$(find_matlab)")"
  if [ ! -d "${share_dir}/venv" ]; then
    mkdir -p "${share_dir}"
    python3 -m venv "${share_dir}/venv"
    "${share_dir}/venv/bin/pip" install jupyter-matlab-proxy jupyterlab
  fi

  . "${share_dir}/venv/bin/activate"
  export PATH="${matlab_dir}:${PATH}"
  jupyter lab "$@"
}

#######################################
# Subcommand to execute Matlab code.
#######################################
run() {
  batch='' command='' debug='' display='-nodisplay' flag='-r' interactive=''
  license='' logfile='' pathcmd='' print='' script='' startdir=''

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      -a | --addpath)
        pathcmd="addpath('${2}'); "
        shift 2
        ;;
      -b | --batch)
        batch='true'
        shift 1
        ;;
      -c | --license)
        license="${2}"
        shift 2
        ;;
      -d | --debug)
        debug='true'
        shift 1
        ;;
      -e | --echo)
        print='true'
        shift 1
        ;;
      -g | --genpath)
        # shellcheck disable=SC2089
        pathcmd="addpath(genpath('${2}')); "
        shift 2
        ;;
      -h | --help)
        usage 'run'
        exit 0
        ;;
      -i | --interactive)
        interactive='true'
        shift 1
        ;;
      -l | -logfile | --logfile)
        logfile="${2}"
        shift 2
        ;;
      -s | -sd | --sd)
        startdir="${2}"
        shift 2
        ;;
      *)
        script="${1}"
        shift 1
        break
        ;;
    esac
  done

  # Build Matlab command for execution.
  #
  # Defaults to batch mode for script execution and interactive mode otherwise.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  module="$(get_module "${script}")"
  if [ -n "${script}" ]; then
    if [ -n "${debug}" ]; then
      command="dbstop if error; dbstop in ${module}; ${module}; exit"
    elif [ -n "${interactive}" ]; then
      command="${module}"
    else
      command="${module}"
      display='-nodesktop'
      flag='-batch'
    fi
  elif [ -n "${batch}" ]; then
    display='-nodesktop'
    flag='-batch'
  elif [ -n "${debug}" ]; then
    command='dbstop if error;'
  fi

  # Add parent path to Matlab if command is a script.
  #
  # Flags:
  #   -n: Check if string has nonzero length.
  if [ -n "${script}" ] && [ "${module}" != "${script}" ]; then
    folder="$(dirname "${script}")"
    case "$(basename "${folder}")" in
      +*) ;;
      *)
        command="addpath('${folder}'); ${command}"
        ;;
    esac
  fi

  command="${pathcmd}${command}"
  program="$(find_matlab)"
  # shellcheck disable=SC2090
  ${print:+echo} "${program}" ${license:+-c "${license}"} \
    ${logfile:+-logfile "${logfile}"} ${startdir:+-sd "${startdir}"} \
    "${display}" -nosplash ${command:+"${flag}"} ${command:+"${command}"}
}

#######################################
# Print Mlab version string.
# Outputs:
#   Mlab version string.
#######################################
version() {
  echo 'Mlab 0.0.4'
}

#######################################
# Script entrypoint.
#######################################
main() {
  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -h | --help)
        usage 'main'
        exit 0
        ;;
      -v | --version)
        version
        exit 0
        ;;
      jupyter)
        shift 1
        jupyter "$@"
        exit 0
        ;;
      run)
        shift 1
        run "$@"
        exit 0
        ;;
      *)
        error_usage "No such subcommand or option '${1}'"
        ;;
    esac
  done

  usage 'main'
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
