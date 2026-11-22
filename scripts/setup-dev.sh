#!/bin/bash
# Installs the Homebrew dependencies and mise tools for PassArc development.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcrun --sdk macosx --find swiftc >/dev/null; then
  echo "Install Xcode Command Line Tools with xcode-select --install, or select a working toolchain." >&2
  exit 1
fi

if ! command -v brew >/dev/null; then
  echo "Install Homebrew from https://brew.sh/ and add it to PATH." >&2
  exit 1
fi

missing=()
for formula in sevenzip zstd age; do
  if ! brew list --versions "$formula" >/dev/null; then
    missing+=("$formula")
  fi
done
if ! command -v mise >/dev/null; then
  missing+=(mise)
fi
if (("${#missing[@]}" > 0)); then
  brew install "${missing[@]}"
fi

mise trust mise.toml
mise install
