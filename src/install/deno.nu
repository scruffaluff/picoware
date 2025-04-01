#!/usr/bin/env nu

# Find command to elevate as super user.
def find_super [] {
    if (is-admin) {
        ""
    } else if (which doas | is-not-empty) {
        "doas"
    } else if (which sudo | is-not-empty) {
        "sudo"
    } else {
        error make {
            msg: "Unable to find a command for super user elevation."
        }
    }
}

# Check if super user elevation is required.
def need_super [$dest: string, global: bool] {
    if $global {
        return true
    }
    try { mkdir $dest } catch { return true }
    try { touch $"($dest)/.super_check" } catch { return true }
    rm $"($dest)/.super_check" 
    false
}

# Install Deno for MacOS, Linux, and Windows systems.
def main [
    --dest (-d): string # Directory to install Deno
    --global (-g) # Install Deno for all users
    --modify-env (-m) # Update system environment
    --quiet (-q) # Print only error messages
    --version (-v): string # Version of Deno to install
] {
    # "$Env:LocalAppData\Programs\Bin"
    let dest_ = $dest | default $"($env.HOME)/.local/bin"
    let super = if (need_super $dest_ $global) { find_super } else { "" }
    let version_ = $version
    | default (http get https://dl.deno.land/release-latest.txt)
    
    if (which unzip | is-empty) {
        print --stderr 'error: Unable to find zip file archiver.'
        print --stderr 'Install zip, https://en.wikipedia.org/wiki/ZIP_(file_format), manually before continuing.'
        exit 1
    }

    let arch = $nu.os-info.arch
    let target = match $nu.os-info.name {
        "linux" => $"($nu.os-info.arch)-unknown-linux-gnu"
        "macos" => $"($nu.os-info.arch)-apple-darwin"
        "windows" => $"($nu.os-info.arch)-pc-windows-msvc"
    }

    let temp = mktemp --directory --tmpdir
    if ($super | is-empty) { mkdir $dest_ } else { ^$super mkdir $dest_ }

    print $"Installing Deno to '($dest_)'."
    http get $"https://dl.deno.land/release/($version_)/deno-($target).zip"
    | save $"($temp)/deno.zip"
    unzip -d $temp $"($temp)/deno.zip"
    if ($super | is-empty) {
        mv $"($temp)/deno" $"($dest_)/deno"
    } else { 
        ^$super mv $"($temp)/deno" $"($dest_)/deno"
    }

    # Update shell profile if destination is not in system path.
    if $modify_env and not $dest_ in $env.PATH {
        print 'Not yet implemented'
    }

    $env.PATH = $env.PATH | prepend $dest_
    print $"Installed (deno --version)."
}
