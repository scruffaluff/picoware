# Just configuration file for running commands.
#
# For more information, visit https://just.systems.

set windows-shell := ['powershell.exe', '-NoLogo', '-Command']
export PATH := if os() == "windows" {
  justfile_dir() / ".vendor/bin;" + env_var("Path")
} else {
  justfile_dir() / ".vendor/bin:" + justfile_dir() / 
  ".vendor/lib/bats-core/bin:" + env_var("PATH")
}

# List all commands available in justfile.
list:
  just --list

# Execute all commands.
all: setup format lint doc test

# Build documentation.
[unix]
doc:
  cp -r src/install doc/public/
  deno run --allow-all npm:vitepress build .

# Check code formatting.
[unix]
format:
  deno run --allow-all npm:prettier --check .

# Check code formatting.
[windows]
format:
  deno run --allow-all npm:prettier --check .
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings CodeFormatting
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings CodeFormatting

# Run code analyses.
[unix]
lint:
  #!/usr/bin/env sh
  set -eu
  files="$(find src test -type f -name '*.sh' -o -name '*.bats')"
  for file in ${files}; do
    shellcheck "${file}"
  done

# Run code analyses.
[windows]
lint:
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings PSScriptAnalyzerSettings.psd1
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings PSScriptAnalyzerSettings.psd1

# Install development dependencies.
setup: _setup
  deno install --frozen

[unix]
_setup:
  #!/usr/bin/env sh
  set -eu
  if [ ! -x "$(command -v jq)" ]; then
    ./src/install/jq.sh --dest .vendor/bin
  fi
  jq --version
  if [ ! -x "$(command -v nu)" ]; then
    ./src/install/nushell.sh --dest .vendor/bin
  fi
  echo "Nushell $(nu --version)"
  if [ ! -x "$(command -v deno)" ]; then
    export DENO_INSTALL="$(pwd)/.vendor"
    curl -fsSL https://deno.land/install.sh | sh -s -- --no-modify-path --yes
  fi
  deno --version
  mkdir -p .vendor/bin .vendor/lib
  for spec in 'assert:v2.1.0' 'core:v1.11.1' 'support:v0.3.0'; do
    pkg="${spec%:*}"
    tag="${spec#*:}"
    if [ ! -d ".vendor/lib/bats-${pkg}" ]; then
      git clone --branch "${tag}" --depth 1 \
        "https://github.com/bats-core/bats-${pkg}.git" ".vendor/lib/bats-${pkg}"
    fi
  done
  bats --version

[windows]
_setup:
  #!powershell.exe
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  $PSNativeCommandUseErrorActionPreference = $True
  # If executing task from PowerShell Core, error such as "'Install-Module'
  # command was found in the module 'PowerShellGet', but the module could not be
  # loaded" unless earlier versions of PackageManagement and PowerShellGet are
  # imported.
  Import-Module -MaximumVersion 1.1.0 -MinimumVersion 1.0.0 PackageManagement
  Import-Module -MaximumVersion 1.9.9 -MinimumVersion 1.0.0 PowerShellGet
  Get-PackageProvider -Force Nuget | Out-Null
  If (-Not (Get-Command -ErrorAction SilentlyContinue jq)) {
    & src/install/jq.ps1 --dest .vendor/bin
  }
  jq --version
  If (-Not (Get-Command -ErrorAction SilentlyContinue nu)) {
    & src/install/nushell.ps1 --dest .vendor/bin
  }
  Write-Output "Nushell $(nu --version)"
  If (-Not (Get-Command -ErrorAction SilentlyContinue deno)) {
    $Env:DENO_INSTALL="$(pwd)/.vendor"
    irm https://deno.land/install.ps1 | iex
  }
  deno --version
  If (-Not (Get-Module -ListAvailable -FullyQualifiedName @{ModuleName="PSScriptAnalyzer";ModuleVersion="1.0.0"})) {
    Install-Module -Force -MinimumVersion 1.0.0 -Name PSScriptAnalyzer
  }
  If (-Not (Get-Module -ListAvailable -FullyQualifiedName @{ModuleName="Pester";ModuleVersion="5.0.0"})) {
    Install-Module -Force -SkipPublisherCheck -MinimumVersion 5.0.0 -Name Pester
  }
  Install-Module -Force -Name PSScriptAnalyzer
  Install-Module -Force -SkipPublisherCheck -Name Pester

# Run test suites.
[unix]
test:
  bats --recursive test

# Run test suites.
[windows]
test:
  Invoke-Pester -CI -Output Detailed test
