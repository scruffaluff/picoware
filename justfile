# Just configuration file for running commands.
#
# For more information, visit https://just.systems.

set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
export PATH := if os() == "windows" {
  join(justfile_dir(), ".vendor\\bin;") + env("Path")
} else {
  justfile_dir() / ".vendor/bin:" + justfile_dir() / 
  ".vendor/lib/bats-core/bin:" + env("PATH")
}
export PSModulePath := if os() == "windows" {
  join(justfile_dir(), ".vendor\\lib\\powershell\\modules;") + 
  env("PSModulePath", "")
} else { "" }

# List all commands available in justfile.
list:
  just --list

# Execute CI workflow commands.
ci: setup lint doc test

# Build documentation.
[unix]
doc:
  cp -r src/action src/install data/public/
  deno run --allow-all npm:vitepress build .

# Build documentation.
[windows]
doc:
  Copy-Item -Force -Recurse -Path src/action -Destination data/public/
  Copy-Item -Force -Recurse -Path src/install -Destination data/public/
  deno run --allow-all npm:vitepress build .

# Fix code formatting.
[unix]
format:
  npx prettier --write .
  shfmt --write src test
  uv tool run ruff format .

# Fix code formatting.
[windows]
format:
  #!powershell.exe
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  $PSNativeCommandUseErrorActionPreference = $True
  npx prettier --write .
  Invoke-ScriptAnalyzer -Fix -Recurse -Path src -Setting CodeFormatting
  Invoke-ScriptAnalyzer -Fix -Recurse -Path test -Setting CodeFormatting
  $Scripts = Get-ChildItem -Recurse -Filter *.ps1 -Path src, test
  foreach ($Script in $Scripts) {
    $Text = Get-Content -Raw $Script.FullName
    [System.IO.File]::WriteAllText($Script.FullName, $Text)
  }
  uv tool run ruff format .

# Run code analyses.
[unix]
lint:
  #!/usr/bin/env sh
  set -eu
  deno run --allow-all npm:prettier --check .
  shfmt --diff src test
  files="$(find src test -name '*.sh' -or -name '*.bats')"
  for file in ${files}; do
    shellcheck "${file}"
  done
  uv tool run ruff format --check .
  uv tool run ruff check .

# Run code analyses.
[windows]
lint:
  deno run --allow-all npm:prettier --check .
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings CodeFormatting
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings CodeFormatting
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings \
    data/config/script_analyzer.psd1
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings \
    data/config/script_analyzer.psd1
  uv tool run ruff format --check .
  uv tool run ruff check .

# Install development dependencies.
[unix]
setup:
  #!/usr/bin/env sh
  set -eu
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  if [ ! -x "$(command -v jq)" ]; then
    src/install/jq.sh --preserve-env --dest .vendor/bin
  fi
  jq --version
  if [ ! -x "$(command -v nu)" ]; then
    src/install/nushell.sh --preserve-env --dest .vendor/bin
  fi
  echo "Nushell $(nu --version)"
  if [ ! -x "$(command -v deno)" ]; then
    src/install/deno.sh --preserve-env --dest .vendor/bin
  fi
  deno --version
  if [ ! -x "$(command -v uv)" ]; then
    src/install/uv.sh --preserve-env --dest .vendor/bin
  fi
  uv --version
  mkdir -p .vendor/bin .vendor/lib
  for spec in 'assert:v2.1.0' 'core:v1.11.1' 'file:v0.4.0' 'support:v0.3.0'; do
    pkg="${spec%:*}"
    tag="${spec#*:}"
    if [ ! -d ".vendor/lib/bats-${pkg}" ]; then
      git clone -c advice.detachedHead=false --branch "${tag}" --depth 1 \
        "https://github.com/bats-core/bats-${pkg}.git" ".vendor/lib/bats-${pkg}"
    fi
  done
  bats --version
  if [ ! -d .vendor/lib/nutest ]; then
    git clone -c advice.detachedHead=false --branch v1.1.0 --depth 1 \
      https://github.com/vyadh/nutest.git .vendor/lib/nutest
  fi
  if [ ! -x "$(command -v shellcheck)" ]; then
    shellcheck_arch="$(uname -m | sed 's/amd64/x86_64/;s/x64/x86_64/;s/arm64/aarch64/')"
    shellcheck_version="$(curl  --fail --location --show-error \
      https://formulae.brew.sh/api/formula/shellcheck.json |
      jq --exit-status --raw-output .versions.stable)"
    curl --fail --location --show-error --output /tmp/shellcheck.tar.xz \
      https://github.com/koalaman/shellcheck/releases/download/v${shellcheck_version}/shellcheck-v${shellcheck_version}.${os}.${shellcheck_arch}.tar.xz
    tar fx /tmp/shellcheck.tar.xz -C /tmp
    install "/tmp/shellcheck-v${shellcheck_version}/shellcheck" .vendor/bin/
  fi
  shellcheck --version
  if [ ! -x "$(command -v shfmt)" ]; then
    shfmt_arch="$(uname -m | sed 's/x86_64/amd64/;s/x64/amd64/;s/aarch64/arm64/')"
    shfmt_version="$(curl  --fail --location --show-error \
      https://formulae.brew.sh/api/formula/shfmt.json |
      jq --exit-status --raw-output .versions.stable)"
    curl --fail --location --show-error --output .vendor/bin/shfmt \
      "https://github.com/mvdan/sh/releases/download/v${shfmt_version}/shfmt_v${shfmt_version}_${os}_${shfmt_arch}"
    chmod 755 .vendor/bin/shfmt
  fi
  echo "Shfmt $(shfmt --version)"
  if [ "${JUST_INIT:-}" = 'init' ]; then
    deno install
  else
    deno install --frozen
  fi

# Install development dependencies.
[windows]
setup:
  #!powershell.exe
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  $PSNativeCommandUseErrorActionPreference = $True
  $ModulePath = '.vendor\lib\powershell\modules'
  New-Item -Force -ItemType Directory -Path $ModulePath | Out-Null
  if (-not (Get-Command -ErrorAction SilentlyContinue jq)) {
    src/install/jq.ps1 --preserve-env --dest .vendor/bin
  }
  jq --version
  if (-not (Get-Command -ErrorAction SilentlyContinue nu)) {
    src/install/nushell.ps1 --preserve-env --dest .vendor/bin
  }
  Write-Output "Nushell $(nu --version)"
  if (-not (Get-Command -ErrorAction SilentlyContinue deno)) {
    src/install/deno.ps1 --preserve-env --dest .vendor/bin
  }
  deno --version
  if (-not (Get-Command -ErrorAction SilentlyContinue uv)) {
    src/install/uv.ps1 --preserve-env --dest .vendor/bin
  }
  uv --version
  if (-not (Test-Path -Path .vendor/lib/nutest -PathType Container)) {
    git clone -c advice.detachedHead=false --branch v1.1.0 --depth 1 `
      https://github.com/vyadh/nutest.git .vendor/lib/nutest
  }
  # If executing task from PowerShell Core, error such as "'Install-Module'
  # command was found in the module 'PowerShellGet', but the module could not be
  # loaded" unless earlier versions of PackageManagement and PowerShellGet are
  # imported.
  Import-Module -MaximumVersion 1.1.0 -MinimumVersion 1.0.0 PackageManagement
  Import-Module -MaximumVersion 1.9.9 -MinimumVersion 1.0.0 PowerShellGet
  Get-PackageProvider -Force Nuget | Out-Null
  if (
    -not (Get-Module -ListAvailable -FullyQualifiedName `
    @{ModuleName = 'PSScriptAnalyzer'; ModuleVersion = '1.0.0' })
  ) {
    Find-Module -MinimumVersion 1.0.0 -Name PSScriptAnalyzer | Save-Module `
      -Force -Path $ModulePath
  }
  if (
    -not (Get-Module -ListAvailable -FullyQualifiedName `
    @{ModuleName = 'Pester'; ModuleVersion = '5.0.0' })
  ) {
    Find-Module -MinimumVersion 5.0.0 -Name Pester | Save-Module -Force -Path `
      $ModulePath
  }
  if ("$Env:JUST_INIT" -eq 'init') {
    deno install
  }
  else {
    deno install --frozen
  }

# Run test suites.
[unix]
test *args: && test-nushell test-python
  bats --recursive test {{args}}

# Run test suites.
[windows]
test: && test-nushell test-python
  Invoke-Pester -CI -Output Detailed -Path \
    $(Get-ChildItem -Recurse -Filter *.test.ps1 -Path test).FullName

# Run Nushell test suite.
test-nushell *args:
  nu --commands \
    "use .vendor/lib/nutest/nutest run-tests; run-tests --path test {{args}}"

# Run Python test suite.
test-python *args:
  uv tool run --python 3.12 --with loguru,typer,pyyaml pytest test {{args}}
