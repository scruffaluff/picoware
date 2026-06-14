#!/usr/bin/env nu

# Set Zellij layout with initialization paths.
def layout [path: path] {
    $'
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:compact-bar"
        }
        children
        pane size=1 borderless=true {
            plugin location="zellij:status-bar"
        }
    }
    tab {
        pane split_direction="vertical" {
            pane command="zhy" size="20%" {
                args "file" "($path)"
            }
            pane size="80%" split_direction="horizontal" {
                pane command="zhy" size="68%" {
                    args "edit" "--init" "($path)"
                    focus true
                }
                pane size="32%"
            }
        }
    }
}
'
    | str trim
}

# Fetch Zellij terminal panes.
def list-panes [] {
    zellij action list-panes --json
    | from json
    | where is_plugin == false
}

# Launch Zellij as an integrated development environment.
def main [
    --version (-v) # Print version information
    path: path = "." # Input path
] {
    if $version {
        print "Zhy 0.0.1"
        return
    }

    if ("ZELLIJ" in $env) {
        if (list-panes | length) == 1 {
            (
                zellij action override-layout --apply-only-to-active-tab
                --layout-string (layout $path)
            )
        } else {
            main edit $path
        }
    } else {
        zellij --layout-string (layout $path)
    }
}

# Open file editor in Zhy pane.
def "main edit" [
    --init (-i) # Setup pane metadata
    path: path # Input path
] {
    let config = path-config
    let pane_file = $"($config)/editor_pane"

    if $init {
        mkdir $config
        $env.ZELLIJ_PANE_ID | save --force $pane_file
        hx $path
    } else {
        let id = open $pane_file
        zellij action focus-pane-id $id
        # Press escape key before sending Helix command.
        zellij action write 27
        zellij action write-chars $":open ($path | path expand)"
        # Send Helix command with enter key.
        zellij action write 13
    }
}

# Open file manager in Zhy pane.
def "main file" [
    path: path # Input path
] {
    let home = path-home
    let yazi_config = match $nu.os-info.name {
        windows => $"($home)/AppData/Roaming/yazi"
        _ => $"($home)/.config/yazi"
    }
    let temp = mktemp --dry --directory --tmpdir

    cp --recursive $yazi_config $temp
    open $"($temp)/yazi.toml"
    | update mgr.ratio [0 1 0]
    | save --force $"($temp)/yazi.toml"
    with-env { EDITOR: "zhy" YAZI_CONFIG_HOME: $temp } { yazi $path }
}

# Get Zhy configuration folder.
def path-config [] {
    let home = path-home
    match $nu.os-info.name {
        macos => $"($home)/Library/Application Support/zhy"
        windows => $"($home)/AppData/Roaming/zhy"
        _ => $"($home)/.config/zhy"
    }
}

# Get user home folder.
def path-home [] {
    if $nu.os-info.name == "windows" {
        $env.HOME? | default $"($env.HOMEDRIVE?)($env.HOMEPATH?)"
    } else {
        $env.HOME?
    }
}
