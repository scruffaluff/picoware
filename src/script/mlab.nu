#!/usr/bin/env nu

# Find Matlab executable path.
def find_matlab [path: string] {
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
        $"(glob $search.pattern | get 0)/bin/matlab($search.extension)"
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
        "Mlab 0.1.0"
    } else {
        help main
    }
}

# Print MAT file contents as JSON.
def "main dump" [
    --matlab (-m): string # Custom Matlab executable path
    --pretty (-p) # Pretty format output JSON
    file: string # MAT file path
] {
    let encode = if $pretty {
        $"jsonencode\(load\('($file)'\), PrettyPrint=true\)"
    } else {
        $"jsonencode\(load\('($file)'\)\)"
    }
    let command = $"fprintf\('%s\\n', ($encode)\);"
    let program = find_matlab $"($matlab)"
    ^$program -nojvm -nosplash -batch $command
}

# Launch Jupyter Lab with the Matlab kernel.
def --wrapped "main jupyter" [
    --matlab (-m): string # Custom Matlab executable path
    ...$args: string # Arguments to Jupyter Lab
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
    --addpath (-a): string # Add folder to Matlab path
    --debug (-d) # Launch in Matlab debugger
    --genpath (-g): string # Add folder and recursive children to Matlab path
    --jvm (-j) # Enable Java virtual machine
    --license (-c): string # Location of Matlab license file
    --logfile (-l): string # Copy command window output to logfile
    --matlab (-m): string # Custom Matlab executable path
    --script (-s) # Run Matlab script
    --sd: string # Set the Matlab startup folder
    --shebang # Strip shebang from start of script
    command: string = "" # Matlab command or script path
    ...$args: string # Arguments to Matlab script
] {
    mut flags = ["-nosplash"]
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

    mut setup = ""
    if ($addpath | is-not-empty) {
        $setup = $"addpath\('($addpath)'\); ($setup)"
    }
    if ($genpath | is-not-empty) {
        $setup = $"addpath\(genpath\('($genpath)'\)\); ($setup)"
    }
    
    let program = find_matlab $"($matlab)"
    if $script {
        script $program $shebang $debug $flags $setup $command $args
    } else if ($command | is-not-empty) {
        ^$program ...$flags -batch $command
    } else {
        ^$program ...$flags
    }
}

def script [
    program: string
    shebang: bool
    debug: bool
    flags: list<string>
    setup: string
    module: string
    args: list<string>
] {
    # Script must end in the ".m" extension to be discoverable by Matlab.
    let parts = $module | path parse
    let function = $parts.stem
    let call = $"($function) ($args | str join ' ');"
    let folder = if $shebang {
        let temp_dir = mktemp --directory --tmpdir
        let temp_file = $"($temp_dir)/($parts.stem).m"
        open --raw $module | lines | skip 1 | to text | save --force $temp_file
        $temp_dir
    } else {
        $parts.parent
    }

    let setup = $"($setup)addpath\('($folder)'\); "
    if $debug {
        let command = $"dbstop if error; dbstop in ($function); ($call); exit;"
        ^$program ...$flags -r $"($setup)($command)"
    } else {
        ^$program ...$flags -batch $"($setup)($call)"
    }
}
