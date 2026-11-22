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
APP="$ROOT/build/scripts/PassArc.app"
/usr/bin/ditto -c -k --keepParent "$APP" "$WORK/PassArc-arm64.zip"
if [[ -n "${PASSARC_NOTARY_KEY:-}" ]]; then
  xcrun notarytool submit "$WORK/PassArc-arm64.zip" --wait \
    --key "$PASSARC_NOTARY_KEY" --key-id "${PASSARC_NOTARY_KEY_ID:?}" \
    --issuer "${PASSARC_NOTARY_ISSUER:?}"
  xcrun stapler staple "$APP"
  rm "$WORK/PassArc-arm64.zip"
  /usr/bin/ditto -c -k --keepParent "$APP" "$WORK/PassArc-arm64.zip"
fi
# Verify the extracted bundle as well as the source bundle checked by build.sh.
/usr/bin/ditto -x -k "$WORK/PassArc-arm64.zip" "$WORK/extracted"
/usr/bin/codesign --verify --deep --strict "$WORK/extracted/PassArc.app"
if [[ -n "${PASSARC_NOTARY_KEY:-}" ]]; then
  xcrun stapler validate "$WORK/extracted/PassArc.app"
  /usr/sbin/spctl --assess --type execute --verbose "$WORK/extracted/PassArc.app"
fi
SHA256="$(/usr/bin/shasum -a 256 "$WORK/PassArc-arm64.zip")"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/${SHA256%% *}/" \
  "$ROOT/homebrew/passarc.rb.in" >"$WORK/passarc.rb"
ruby -c "$WORK/passarc.rb"
mv -f "$WORK/PassArc-arm64.zip" "$ARCHIVE"
mv -f "$WORK/passarc.rb" "$OUT/passarc.rb"
