#!/bin/bash
# Usage: scripts/package-release.sh <version>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/PassArc-arm64.zip"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <major.minor.patch>" >&2
  exit 1
fi

PASSARC_BUILD_VERSION="$VERSION" "$ROOT/scripts/build.sh"
mkdir -p "$OUT"
# ditto updates existing archives, so write a fresh archive on each run.
WORK="$(mktemp -d "$OUT/.package.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
/usr/bin/ditto -c -k --keepParent "$ROOT/build/scripts/PassArc.app" "$WORK/PassArc-arm64.zip"
# Verify the extracted bundle as well as the source bundle checked by build.sh.
/usr/bin/ditto -x -k "$WORK/PassArc-arm64.zip" "$WORK/extracted"
/usr/bin/codesign --verify --deep --strict "$WORK/extracted/PassArc.app"
SHA256="$(/usr/bin/shasum -a 256 "$WORK/PassArc-arm64.zip")"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/${SHA256%% *}/" \
  "$ROOT/homebrew/passarc.rb.in" > "$WORK/passarc.rb"
ruby -c "$WORK/passarc.rb"
mv -f "$WORK/PassArc-arm64.zip" "$ARCHIVE"
mv -f "$WORK/passarc.rb" "$OUT/passarc.rb"
