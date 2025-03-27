---
prev:
  text: Home
  link: /
---

# Installation

Scripts provides Bash and PowerShell installer scripts to download any
collection of scripts from the repository.

::: warning

On Windows, PowerShell will need to run as administrator if the `--global` flag
is used. Additionally, the security policy must allow for running remote
PowerShell scripts. If needed, the following command will update the security
policy for the current user.

:::

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Installers

The installer programs, from the following table, can be executed by piping them
into Bash and PowerShell for Unix systems and Windows respectively.

| Name    | Description                                         |
| ------- | --------------------------------------------------- |
| deno    | Installs Deno JavaScript runtime.                   |
| jq      | Installs Jq JSON parser.                            |
| just    | Installs Just command runner.                       |
| nushell | Installs Nushell structured data shell.             |
| scripts | Installs programs from the following scripts table. |
| uv      | Installs Uv Python package manager.                 |

The following command installs Nushell. To execute the other installers, replace
`nushell` with the installer name.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/install/nushell.sh | sh
```

```powershell [Windows]
iwr -useb https://scruffaluff.github.io/scripts/install/nushell.ps1 | iex
```

:::

To view usage options, run the following command.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/install/nushell.sh | sh -s -- --help
```

```powershell [Windows]
powershell { iex "& { $(iwr -useb https://scruffaluff.github.io/scripts/install/nushell.ps1) } --help" }
```

:::

## Scripts

The programs, from the following table, can be installed with the
https://scruffaluff.github.io/scripts/install/scripts.sh for Unix systems and
https://scruffaluff.github.io/scripts/install/scripts.ps1 for Windows.

| Name        | Description                                    |
| ----------- | ---------------------------------------------- |
| caffeinate  | Prevent system from sleeping during a program. |
| clear-cache | Remove package manager caches.                 |
| mlab        | Wrapper script for running Matlab as a CLI.    |
| rgi         | Interactive Ripgrep searcher.                  |
| trsync      | Rsync for one time remote connections.         |
| tscp        | SCP for one time remote connections.           |
| tssh        | SSH for one time remote connections.           |

The following command will install the clear-cache and rgi scripts. Other
scripts can be installed by replacing the program names.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/install/scripts.sh | sh -s -- clear-cache rgi
```

```powershell [Windows]
powershell { iex "& { $(iwr -useb https://scruffaluff.github.io/scripts/install/scripts.ps1) } clear-cache rgi" }
```

:::

To view usage options, run the following command.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/install/scripts.sh | sh -s -- --help
```

```powershell [Windows]
powershell { iex "& { $(iwr -useb https://scruffaluff.github.io/scripts/install/scripts.ps1) } --help" }
```

:::

## Actions

The one-time usage programs, from the following table, can be executed by piping
them into Bash and PowerShell for Unix systems and Windows respectively.

| Name          | Description                                    |
| ------------- | ---------------------------------------------- |
| purge-snap    | Remove all traces of the Snap package manager. |
| tmate-session | Install and run Tmate for CI pipelines.        |

The following command runs the Tmate Session script. To execute the other
actions, replace `tmate-session` with the installer name.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/action/tmate-session.sh | sh
```

```powershell [Windows]
iwr -useb https://scruffaluff.github.io/scripts/action/tmate-session.ps1 | iex
```

:::

To view usage options, run the following command.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/action/tmate-session.sh | sh -s -- --help
```

```powershell [Windows]
powershell { iex "& { $(iwr -useb https://scruffaluff.github.io/scripts/action/tmate-session.ps1) } --help" }
```

:::
