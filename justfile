# Just configuration file for running commands.
#
# For more information, visit https://just.systems.

set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
export PATH := if os() == "windows" {
  join(justfile_directory(), ".vendor\\bin;") + env("PATH")
} else {
  justfile_directory() / ".vendor/bin:" + justfile_directory() /
  ".vendor/lib/bats-core/bin:" + env("PATH")
}
export PSModulePath := if os() == "windows" {
  join(justfile_directory(), ".vendor\\lib\\powershell\\modules;") +
  env("PSModulePath", "")
} else { "" }
export UV_PYTHON := "~=3.11"

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

# Fix code formatting.
[unix]
format +paths=".":
  npx prettier --write {{paths}}
  shfmt --write src test
  uv tool run ruff format {{paths}}

# Fix code formatting.
[windows]
format +paths=".":
  #!powershell.exe
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  $PSNativeCommandUseErrorActionPreference = $True
  npx prettier --write {{paths}}
  Invoke-ScriptAnalyzer -Fix -Recurse -Path src -Settings CodeFormatting
  Invoke-ScriptAnalyzer -Fix -Recurse -Path test -Settings CodeFormatting
  $Scripts = Get-ChildItem -Recurse -Filter *.ps1 -Path src, test
  foreach ($Script in $Scripts) {
    $Text = Get-Content -Raw $Script.FullName
    [System.IO.File]::WriteAllText($Script.FullName, $Text)
  }
  uv tool run ruff format {{paths}}

# Install project programs.
install workflow *args:
  nu src/install/{{workflow}}.nu --version {{justfile_directory()}} {{args}}

# Run code analyses.
[unix]
lint +paths=".":
  #!/usr/bin/env sh
  set -eu
  deno run --allow-all npm:prettier --check {{paths}}
  shfmt --diff src test
  files="$(find src test -name '*.sh' -or -name '*.bats')"
  for file in ${files}; do
    shellcheck "${file}"
  done
  uv tool run ruff format --check {{paths}}
  uv tool run ruff check {{paths}}
  uv tool run ty check {{paths}}

# Run code analyses.
[windows]
lint +paths=".":
  deno run --allow-all npm:prettier --check {{paths}}
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings CodeFormatting
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings CodeFormatting
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings \
    data/config/script_analyzer.psd1
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings \
    data/config/script_analyzer.psd1
  uv tool run ruff format --check {{paths}}
  uv tool run ruff check {{paths}}
  uv tool run ty check {{paths}}

# List all commands available in justfile.
[default]
list:
  @just --list

# Install development dependencies.
[unix]
setup:
  #!/usr/bin/env sh
  set -eu
  arch='{{replace(replace(arch(), "x86_64", "amd64"), "aarch64", "arm64")}}'
  os='{{replace(os(), "macos", "darwin")}}'
  mkdir -p .vendor/bin .vendor/lib
  if ! command -v jq > /dev/null 2>&1; then
    echo 'Installing Jq.'
    src/install/jq.sh --preserve-env --dest .vendor/bin
  fi
  echo "Using $(jq --version)."
  if ! command -v nu > /dev/null 2>&1; then
    echo 'Installing Nushell.'
    src/install/nushell.sh --preserve-env --dest .vendor/bin
  fi
  echo "Using Nushell $(nu --version)."
  if ! command -v deno > /dev/null 2>&1; then
    echo 'Installing Deno.'
    src/install/deno.sh --preserve-env --dest .vendor/bin
  fi
  echo "Using $(deno -V)."
  if ! command -v uv > /dev/null 2>&1; then
    echo 'Installing Uv.'
    src/install/uv.sh --preserve-env --dest .vendor/bin
  fi
  echo "Using $(uv --version)."
  for spec in 'assert:v2.1.0' 'core:v1.11.1' 'file:v0.4.0' 'support:v0.3.0'; do
    bats_check=''
    pkg="${spec%:*}"
    tag="${spec#*:}"
    if [ ! -d ".vendor/lib/bats-${pkg}" ]; then
      if [ -z "${bats_check}" ]; then
        echo 'Installing Bats.'
        bats_check='1'
      fi
      git clone -c advice.detachedHead=false --branch "${tag}" --depth 1 \
        "https://github.com/bats-core/bats-${pkg}.git" ".vendor/lib/bats-${pkg}"
    fi
  done
  echo "Using $(bats --version)."
  if [ ! -d .vendor/lib/nutest ]; then
    echo 'Installing Nutest.'
    git clone -c advice.detachedHead=false --branch main \
      --depth 1 https://github.com/vyadh/nutest.git .vendor/lib/nutest
  fi
  echo "Using Nutest $(git -C .vendor/lib/nutest rev-parse HEAD)."
  if ! command -v shellcheck > /dev/null 2>&1; then
    echo 'Installing ShellCheck.'
    shellcheck_arch='{{arch()}}'
    shellcheck_version="$(curl --fail --location --show-error \
      https://formulae.brew.sh/api/formula/shellcheck.json |
      jq --exit-status --raw-output .versions.stable)"
    curl --fail --location --show-error --output /tmp/shellcheck.tar.xz \
      "https://github.com/koalaman/shellcheck/releases/download/v${shellcheck_version}/shellcheck-v${shellcheck_version}.${os}.${shellcheck_arch}.tar.xz"
    tar fx /tmp/shellcheck.tar.xz -C /tmp
    install "/tmp/shellcheck-v${shellcheck_version}/shellcheck" .vendor/bin/
  fi
  echo "Using $(shellcheck --version)."
  if ! command -v shfmt > /dev/null 2>&1; then
    echo 'Installing Shfmt.'
    shfmt_version="$(curl --fail --location --show-error \
      https://formulae.brew.sh/api/formula/shfmt.json |
      jq --exit-status --raw-output .versions.stable)"
    curl --fail --location --show-error --output .vendor/bin/shfmt \
      "https://github.com/mvdan/sh/releases/download/v${shfmt_version}/shfmt_v${shfmt_version}_${os}_${arch}"
    chmod 755 .vendor/bin/shfmt
  fi
  echo "Using Shfmt $(shfmt --version)."
  echo 'Installing packages with Deno.'
  if [ -n "${JUST_INIT:-}" ]; then
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
    Write-Output 'Installing Jq.'
    src/install/jq.ps1 --preserve-env --dest .vendor/bin
  }
  Write-Output "Using $(jq --version)."
  if (-not (Get-Command -ErrorAction SilentlyContinue nu)) {
    Write-Output 'Installing Nushell.'
    src/install/nushell.ps1 --preserve-env --dest .vendor/bin
  }
  Write-Output "Using Nushell $(nu --version)"
  if (-not (Get-Command -ErrorAction SilentlyContinue deno)) {
    Write-Output 'Installing Deno.'
    src/install/deno.ps1 --preserve-env --dest .vendor/bin
  }
  Write-Output "Using $(deno -V)."
  if (-not (Get-Command -ErrorAction SilentlyContinue uv)) {
    Write-Output 'Installing Uv.'
    src/install/uv.ps1 --preserve-env --dest .vendor/bin
  }
  Write-Output "Using $(uv --version)."
  if (-not (Test-Path -Path .vendor/lib/nutest -PathType Container)) {
    Write-Output 'Installing Nutest.'
    git clone -c advice.detachedHead=false --branch main --depth 1 `
      https://github.com/vyadh/nutest.git .vendor/lib/nutest
  }
  Write-Output "Using Nutest $(git -C .vendor/lib/nutest rev-parse HEAD)."
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
    Write-Output 'Installing PSScriptAnalyzer.'
    Find-Module -MinimumVersion 1.0.0 -Name PSScriptAnalyzer | Save-Module `
      -Force -Path $ModulePath
  }
  Write-Output "Using PSScriptAnalyzer $((Get-Module -ListAvailable `
    PSScriptAnalyzer | Select-Object -First 1).Version)."
  if (
    -not (Get-Module -ListAvailable -FullyQualifiedName `
    @{ModuleName = 'Pester'; ModuleVersion = '5.0.0' })
  ) {
    Write-Output 'Installing Pester.'
    Find-Module -MinimumVersion 5.0.0 -Name Pester | Save-Module -Force -Path `
      $ModulePath
  }
  Write-Output "Using Pester $((Get-Module -ListAvailable Pester | `
    Select-Object -First 1).Version)."
  Write-Output 'Installing packages with Deno.'
  if ("$Env:JUST_INIT") {
    deno install
  }
  else {
    deno install --frozen
  }

# Run test suites.
test: test-shell test-nushell test-python

# Run shell test suites.
[unix]
test-shell *args:
  bats --recursive test {{args}}

# Run PowerShell test suite.
[windows]
test-shell *args:
  Invoke-Pester -CI -Output Detailed -Path \
    $(Get-ChildItem -Recurse -Filter *.test.ps1 -Path test).FullName

# Run Nushell test suite.
test-nushell *args:
  nu --commands \
    "use .vendor/lib/nutest/nutest run-tests; run-tests --fail --path test {{args}}"

# Run Python test suite.
test-python *args:
  uv tool run --python 3.12 --with loguru,typer,pyyaml pytest test {{args}}
