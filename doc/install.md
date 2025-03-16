---
prev:
  text: Home
  link: /
---

# Installation

Scripts provides POSIX shell and PowerShell installer scripts to download any
collection of scripts from the repository. The following command shows the list
of downloadable scripts from the repository.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/install/scripts.sh | sh -s -- --list
```

```powershell [Windows]
powershell { iex "& { $(iwr -useb https://scruffaluff.github.io/scripts/install/scripts.ps1) } --list" }
```

:::

The following command will install the packup script. Other scripts can be
installed by replacing the `packup` argument.

::: code-group

```sh [Unix]
curl -LSfs https://scruffaluff.github.io/scripts/install/scripts.sh | sh -s -- packup
```

```powershell [Windows]
powershell { iex "& { $(iwr -useb https://scruffaluff.github.io/scripts/install/scripts.ps1) } packup" }
```

:::

::: warning

On Windows, PowerShell will need to run as administrator if the `--global` flag
is used. Additionally, the security policy must allow for running remote
PowerShell scripts. If needed, the following command will update the security
policy for the current user.

:::

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
