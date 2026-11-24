#!/bin/bash
set -euo pipefail

if (($# > 1)); then
  echo "Usage: $0 [key-directory]" >&2
  exit 1
fi

if ! command -v age-keygen >/dev/null; then
  echo "Install age with: brew install age" >&2
  exit 1
fi

umask 077
key_directory=${1:-"$HOME/.config/passarc/keys"}
mkdir -p -- "$key_directory"
key_directory=$(cd -- "$key_directory" && pwd)
identity="$key_directory/passarc-identity.txt"
recipient="$key_directory/passarc-recipient.txt"

if [[ -e "$identity" || -L "$identity" || -e "$recipient" || -L "$recipient" ]]; then
  echo "A PassArc key file already exists in $key_directory. Choose another directory to create a new pair." >&2
  exit 1
fi

age-keygen -o "$identity"
age-keygen -y -o "$recipient" "$identity"
printf 'Public key to share: %s\nPrivate key to keep and back up securely: %s\n' "$recipient" "$identity"
