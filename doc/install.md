---
prev:
  text: Home
  link: /
---

# Installation

Picoware provides Bash and PowerShell installer scripts to download any
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
Additionally, the Nushell installer programs work on any platform.

| Name        | Description                                         |
| ----------- | --------------------------------------------------- |
| cargo       | Installs Cargo Rust package manager.                |
| deno        | Installs Deno JavaScript runtime.                   |
| jq          | Installs Jq JSON parser.                            |
| just        | Installs Just command runner.                       |
| nushell     | Installs Nushell structured data shell.             |
| rust-script | Installs Rust Script Rust script executor.          |
| scripts     | Installs programs from the following scripts table. |
| uv          | Installs Uv Python package manager.                 |

The following command installs Deno. To execute the other installers, replace
`deno` with the installer name.

::: code-group

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/install/deno.sh | sh
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/install/deno.ps1)))
```

```nushell [Nushell]
http get https://scruffaluff.github.io/picoware/install/deno.nu | nu -c $"($in | decode); main"
```

:::

To view usage options, run the following command.

::: code-group

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/install/deno.sh | sh -s -- --help
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/install/deno.ps1))) --help
```

```nushell [Nushell]
http get https://scruffaluff.github.io/picoware/install/deno.nu | nu -c $"($in | decode); main --help"
```

:::

## Scripts

The programs, from the following table, can be installed with the
https://scruffaluff.github.io/picoware/install/scripts.sh for Unix systems and
https://scruffaluff.github.io/picoware/install/scripts.ps1 for Windows.

| Name        | Description                                    |
| ----------- | ---------------------------------------------- |
| caffeinate  | Prevent system from sleeping during a program. |
| clear-cache | Remove package manager caches.                 |
| fdi         | Interactive Fd searcher.                       |
| mlab        | Wrapper script for running Matlab as a CLI.    |
| rgi         | Interactive Ripgrep searcher.                  |
| trsync      | Rsync for one time remote connections.         |
| tscp        | SCP for one time remote connections.           |
| tssh        | SSH for one time remote connections.           |
| vimu        | Convenience script for QEMU and Virsh.         |

The following command will install the clear-cache and rgi scripts. Other
scripts can be installed by replacing the program names.

::: code-group

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/install/scripts.sh | sh -s -- clear-cache rgi
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/install/scripts.ps1))) clear-cache rgi
```

```nushell [Nushell]
http get https://scruffaluff.github.io/picoware/install/scripts.nu | nu -c $"($in | decode); main clear-cache rgi"
```

:::

To view usage options, run the following command.

::: code-group

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/install/scripts.sh | sh -s -- --help
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/install/scripts.ps1))) --help
```

```nushell [Nushell]
http get https://scruffaluff.github.io/picoware/install/scripts.nu | nu -c $"($in | decode); main --help"
```

:::

## Apps

The programs, from the following table, can be installed with the
https://scruffaluff.github.io/picoware/install/apps.sh for Unix systems and
https://scruffaluff.github.io/picoware/install/apps.ps1 for Windows.

::: warning

The following apps are demos with little functionality.

:::

| Name    | Description                         |
| ------- | ----------------------------------- |
| augraph | Audio plotting example application. |
| denoui  | Example GUI application with Deno.  |
| rustui  | Example GUI application with Rust.  |

The following command will install the augraph and denoui apps. Other apps can
be installed by replacing the program names.

::: code-group

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/install/apps.sh | sh -s -- augraph denoui
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/install/apps.ps1))) augraph denoui
```

```nushell [Nushell]
http get https://scruffaluff.github.io/picoware/install/apps.nu | nu -c $"($in | decode); main augraph denoui"
```

:::

To view usage options, run the following command.

::: code-group

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/install/apps.sh | sh -s -- --help
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/install/apps.ps1))) --help
```

```nushell [Nushell]
http get https://scruffaluff.github.io/picoware/install/apps.nu | nu -c $"($in | decode); main --help"
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

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/action/tmate-session.sh | sh
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/action/tmate-session.ps1)))
```

:::

To view usage options, run the following command.

::: code-group

```sh [Bash]
curl -LSfs https://scruffaluff.github.io/picoware/action/tmate-session.sh | sh -s -- --help
```

```powershell [PowerShell]
& ([ScriptBlock]::Create((irm https://scruffaluff.github.io/picoware/action/tmate-session.ps1))) --help
```

:::
