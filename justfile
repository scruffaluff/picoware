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

# Execute CI workflow commands.
ci: setup format lint doc test

# Build documentation.
[unix]
doc:
  cp -r src/action src/install data/public/
  deno run --allow-all npm:vitepress build .

# Build documentation.
[windows]
doc:
  Copy-Item -Recurse -Path src/action -Destination data/public/
  Copy-Item -Recurse -Path src/install -Destination data/public/
  deno run --allow-all npm:vitepress build .

# Check code formatting.
[unix]
format:
  deno run --allow-all npm:prettier --check .
  shfmt --diff src test

# Check code formatting.
[windows]
format:
  deno run --allow-all npm:prettier --check .
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings CodeFormatting
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings CodeFormatting

# Fix code formatting.
[unix]
format-fix:
  npx prettier --write .
  shfmt --write src test

# Fix code formatting.
[windows]
format-fix:
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

# Run code analyses.
[unix]
lint:
  #!/usr/bin/env sh
  set -eu
  files="$(find src test -name '*.sh' -or -name '*.bats')"
  for file in ${files}; do
    shellcheck "${file}"
  done

# Run code analyses.
[windows]
lint:
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path src -Settings data/config/script_analyzer.psd1
  Invoke-ScriptAnalyzer -EnableExit -Recurse -Path test -Settings data/config/script_analyzer.psd1

# Install development dependencies.
setup: _setup
  deno install --frozen

[unix]
_setup:
  #!/usr/bin/env sh
  set -eu
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  if [ ! -x "$(command -v jq)" ]; then
    src/install/jq.sh --dest .vendor/bin
  fi
  jq --version
  if [ ! -x "$(command -v nu)" ]; then
    src/install/nushell.sh --dest .vendor/bin
  fi
  echo "Nushell $(nu --version)"
  if [ ! -x "$(command -v deno)" ]; then
    src/install/deno.sh --dest .vendor/bin
  fi
  deno --version
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
  if [ ! -x "$(command -v shellcheck)" ]; then
    shellcheck_arch="$(uname -m | sed s/amd64/x86_64/ | sed s/x64/x86_64/ |
      sed s/arm64/aarch64/)"
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
    shfmt_arch="$(uname -m | sed s/x86_64/amd64/ | sed s/x64/amd64/ |
      sed s/aarch64/arm64/)"
    shfmt_version="$(curl  --fail --location --show-error \
      https://formulae.brew.sh/api/formula/shfmt.json |
      jq --exit-status --raw-output .versions.stable)"
    curl --fail --location --show-error --output .vendor/bin/shfmt \
      "https://github.com/mvdan/sh/releases/download/v${shfmt_version}/shfmt_v${shfmt_version}_${os}_${shfmt_arch}"
    chmod 755 .vendor/bin/shfmt
  fi
  echo "Shfmt $(shfmt --version)"

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
  if (-not (Get-Command -ErrorAction SilentlyContinue jq)) {
    src/install/jq.ps1 --dest .vendor/bin
  }
  jq --version
  if (-not (Get-Command -ErrorAction SilentlyContinue nu)) {
    src/install/nushell.ps1 --dest .vendor/bin
  }
  Write-Output "Nushell $(nu --version)"
  if (-not (Get-Command -ErrorAction SilentlyContinue deno)) {
    src/install/deno.ps1 --dest .vendor/bin
  }
  deno --version
  if (-not (Get-Module -ListAvailable -FullyQualifiedName @{ModuleName = "PSScriptAnalyzer"; ModuleVersion = "1.0.0" })) {
    Install-Module -Force -MinimumVersion 1.0.0 -Name PSScriptAnalyzer
  }
  if (-not (Get-Module -ListAvailable -FullyQualifiedName @{ModuleName = "Pester"; ModuleVersion = "5.0.0" })) {
    Install-Module -Force -SkipPublisherCheck -MinimumVersion 5.0.0 -Name Pester
  }
  Install-Module -Force -Name PSScriptAnalyzer
  Install-Module -Force -SkipPublisherCheck -Name Pester

# Run test suites.
[unix]
test *args:
  bats --recursive test {{args}}

# Run test suites.
[windows]
test:
  Invoke-Pester -CI -Output Detailed -Path \
    $(Get-ChildItem -Recurse -Filter *.test.ps1 -Path test).FullName
