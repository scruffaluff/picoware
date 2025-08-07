#!/usr/bin/env -S nu --no-config-file --stdin

def build-code [setup: string command: string args: list<string>] {
    if ($args | is-empty) {
        $"($setup) ($command); exit;"
    } else {
        $"($setup) ($command) ($args | str join ' '); exit;"
    }
}

# Find Matlab executable path.
def find-matlab [path: path] {
    if ($path | is-not-empty) {
        return $path
    } else if ($env.MLAB_PROGRAM? | is-not-empty) {
        return $env.MLAB_PROGRAM
    }

    let search = match $nu.os-info.name {
        "macos" => { extension: "" pattern: "/Applications/MATLAB_*.app" }
        "windows" => { extension: ".exe" pattern: "C:/Program Files/MATLAB/R*" }
        _ => { extension: "" pattern: "/usr/local/MATLAB/R*" }
    }

    try {
        $"(glob $search.pattern | last)/bin/matlab($search.extension)"
        | path expand
    } catch {
        error make --unspanned {
            help: "Try setting the MLAB_PROGRAM environment variable."
            msg: "Unable to find Matlab installation."
        }
    }
}

# Matlab wrapper for running programs from the command line.
def main [
    --version (-v) # Print version information
] {
    if $version {
        "Mlab 0.1.4"
    } else {
        help main
    }
}

# Print MAT file contents as JSON.
def "main dump" [
    --matlab (-m): string # Custom Matlab executable path
    --pretty (-p) # Pretty format output JSON
    file: path # MAT file path
] {
    let encode = if $pretty {
        $"jsonencode\(load\('($file)'\), PrettyPrint=true\)"
    } else {
        $"jsonencode\(load\('($file)'\)\)"
    }
    let command = $"fprintf\('%s\\n', ($encode)\);"
    let program = find-matlab $"($matlab)"
    ^$program -nodesktop -nojvm -nosplash -batch $command
}

# Launch Jupyter Lab with the Matlab kernel.
def --wrapped "main jupyter" [
    --matlab (-m): path # Custom Matlab executable path
    ...args: string # Arguments to Jupyter Lab
] {
    let venv = match $nu.os-info.name {
        "windows" => $"($env.AppLocalData)/mlab/venv"
        _ => $"($env.HOME)/.local/share/mlab/venv"
    } | path expand
    let venv_bin = match $nu.os-info.name {
        "windows" => { $venv | path join "Scripts" }
        _ => { $venv | path join "bin" }
    }
    let matlab_bin = find_matlab $"($matlab)" | path dirname
    $env.PATH = ($env.PATH | prepend [$venv_bin $matlab_bin])

    if not ($venv | path exists) {
        mkdir ($venv | path dirname)
        python3 -m venv $venv
        pip install jupyter-matlab-proxy jupyterlab
    }
    jupyter lab ...$args
}

# Execute Matlab command or script.
def "main run" [
    --addpath (-a): directory # Add folder to Matlab path
    --batch (-b) # Execute in non-interactive batch mode
    --debug (-d) # Launch in Matlab debugger
    --genpath (-g): directory # Add folder and recursive children to Matlab path
    --jvm (-j) # Enable Java virtual machine
    --license (-c): path # Location of Matlab license file
    --logfile (-l): path # Copy command window output to logfile
    --matlab (-m): path # Custom Matlab executable path
    --script (-s) # Always run command as Matlab script
    --sd: directory # Set the Matlab startup folder
    --shebang # Strip shebang from start of script
    command: string = "" # Matlab command or script path
    ...args: string # Arguments to Matlab script
] {
    mut flags = ["-nodesktop" "-nosplash"]
    if not $jvm {
        $flags = [...$flags "-nojvm"]
    }
    if ($license | is-not-empty) {
        $flags = [...$flags "-license" $license]
    }
    if ($logfile | is-not-empty) {
        $flags = [...$flags "-logfile" $logfile]
    }
    if ($sd | is-not-empty) {
        $flags = [...$flags "-sd" $sd]
    }

    mut setup = "if exist('mlabrc'); mlabrc; end;"
    if ($addpath | is-not-empty) {
        $setup = $"addpath\('($addpath)'\); ($setup)"
    }
    if ($genpath | is-not-empty) {
        $setup = $"addpath\(genpath\('($genpath)'\)\); ($setup)"
    }
    let program = find-matlab $"($matlab)"

    if $shebang or $script or ($command | path parse | get extension) == "m" {
        script $program $shebang $batch $debug $flags $setup $command $args
    } else {
        let code = build-code $setup $command $args

        if ($command | is-empty) {
            ^$program ...$flags
        } else if $debug {
            ^$program ...$flags -r $"dbstop if error; ($code)"
        } else if $batch {
            ^$program ...$flags -batch $code
        } else {
            ^$program ...$flags -r $code
        }
    }
}

def script [
    program: path
    shebang: bool
    batch: bool
    debug: bool
    flags: list<string>
    setup: string
    module: path
    args: list<string>
] {
    # Script must end in the ".m" extension to be discoverable by Matlab.
    let parts = $module | path parse
    let function = $parts.stem

    let folder = if $shebang {
        let temp_dir = mktemp --directory --tmpdir
        let temp_file = $"($temp_dir)/($parts.stem).m"
        open --raw $module | lines | skip 1 | to text | save --force $temp_file
        $temp_dir
    } else {
        $parts.parent
    }

    if $debug {
        let code = (
            build-code
            $"dbstop if error; addpath\('($folder)'\); ($setup) dbstop in ($function);"
            $function $args
        )
        ^$program ...$flags -r $code
    } else {
        let code = (
            build-code $"addpath\('($folder)'\); ($setup)" $function $args
        )

        if $batch {
            ^$program ...$flags -batch $code
        } else {
            ^$program ...$flags -r $code
        }
    }
}
