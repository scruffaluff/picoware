---
next:
  text: Install
  link: /install
---

# Scripts

Scripts is my personal collection of utility applications, installers, and
scripts. For instructions on using these programs, see the
[Install](https://scruffaluff.github.io/scripts/install) section of the
documentation.

## Installers

The following table shows the available installer programs. These are Bash, and
PowerShell scripts that download dependencies, configure system settings, and
install each program for immediate use.

| Name    | Description                                         |
| ------- | --------------------------------------------------- |
| deno    | Installs Deno JavaScript runtime.                   |
| jq      | Installs Jq JSON parser.                            |
| just    | Installs Just command runner.                       |
| nushell | Installs Nushell structured data shell.             |
| scripts | Installs programs from the following scripts table. |

## Scripts

The following table shows the available scripts. These are single file programs
that peform convenience tasks. They can be installed with the repostiory's
`scripts` installer.

| Name        | Description                                     |
| ----------- | ----------------------------------------------- |
| caffeinate  | Prevent system from sleeping during a program.  |
| clear-cache | Remove package manager caches.                  |
| mlab        | Wrapper script for running Matlab as a CLI.     |
| packup      | Upgrade programs from several package managers. |
| rgi         | Interactive Ripgrep searcher.                   |
| trsync      | Rsync for one time remote connections.          |
| tscp        | SCP for one time remote connections.            |
| tssh        | SSH for one time remote connections.            |

## Actions

The following table shows the available action programs. These actions are Bash
and PowerShell scripts that are intended for one-time usage to change system
settings or run a temporary program.

| Name          | Description                                    |
| ------------- | ---------------------------------------------- |
| purge-snap    | Remove all traces of the Snap package manager. |
| tmate-session | Install and run Tmate for CI pipelines.        |
