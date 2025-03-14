# Scripts

![](https://img.shields.io/github/actions/workflow/status/scruffaluff/scripts/build.yaml)
![](https://img.shields.io/github/license/scruffaluff/scripts)
![](https://img.shields.io/github/repo-size/scruffaluff/scripts)

Scripts is my personal collection of utility applications, installers, and
scripts. For instructions on using these programs, see the
[Install](https://scruffaluff.github.io/scripts/install) section of the
documentation.

## Installers

The following table shows the available installer programs. These are POSIX
shell and PowerShell scripts that download dependencies, configure system
settings, and install each program for immediate use.

| Name    | Description                                         |
| ------- | --------------------------------------------------- |
| nushell | Installs Nushell.                                   |
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
| purge-snap  | Remove all traces of the Snap package manager.  |
| rgi         | Interactive Ripgrep searcher.                   |
| run-tmate   | Install and run Tmate for CI pipelines.         |
| trsync      | Rsync for one time remote connections.          |
| tscp        | SCP for one time remote connections.            |
| tssh        | SSH for one time remote connections.            |

## Contributing

For guidance on setting up a development environment and how to make a
contribution, see the
[Contributing Guide](https://github.com/scruffaluff/scripts/blob/main/CONTRIBUTING.md).

## License

Scripts is distributed under a
[MIT license](https://github.com/scruffaluff/scripts/blob/main/LICENSE.md).
