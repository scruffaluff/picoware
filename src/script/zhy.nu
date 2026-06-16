#!/usr/bin/env nu

# Set Zellij layout with initialization paths.
def layout [
    --store (-s): path = "" # Store path override
    path: path # Input path
] {
    let store = $store | default --empty $env.ZHY_STORE?
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
                args "file" "--store" "($store)" "($path)"
            }
            pane size="80%" split_direction="horizontal" {
                pane command="zhy" size="68%" {
                    args "edit" "--store" "($store)" "($path)"
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

    if "ZELLIJ" in $env {
        if "ZHY_STORE" in $env {
            main edit $path
        } else if (list-panes | length) == 1 {
            let store = path-store
            (
                zellij action override-layout --apply-only-to-active-tab
                --layout-string (layout --store $store $path)
            )
        } else {
            error make "Cannot start Zhy inside a Zellij tab with more than one pane."
        }
    } else {
        with-env { ZHY_STORE: (path-store) } {
            zellij --layout-string (layout $path)
        }
    }
}

# Open file editor in Zhy pane.
def "main edit" [
    --store (-s): path = "" # Store path override
    path: path # Input path
] {
    let store_path = $store | default --empty $env.ZHY_STORE?
    let store = open $store_path

    if ("editor" in $store) {
        zellij action focus-pane-id $store.editor
        # Press escape key before sending Helix command.
        zellij action write 27
        zellij action write-chars $":open ($path | path expand)"
        # Send Helix command with enter key.
        zellij action write 13
    } else {
        $store
        | upsert editor $env.ZELLIJ_PANE_ID
        | save --force $store_path
        exec hx $path
    }
}

# Open file manager in Zhy pane.
def "main file" [
    --store (-s): path = "" # Store path override
    path: path # Input path
] {
    let store = $store | default --empty $env.ZHY_STORE?
    with-env { EDITOR: "zhy" ZHY_STORE: $store } { exec yazi $path }
}

# Get store path.
def path-store [] {
    if "ZHY_STORE" in $env {
        $env.ZHY_STORE
    } else {
        let path = mktemp --tmpdir --suffix ".json"
        {} | save --force $path
        $path
    }
}
