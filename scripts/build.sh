#!/bin/bash
# Builds and signs PassArc.app (with its Finder Sync extension) without Xcode.
# Usage: scripts/build.sh [--install]
#   --install copies it to ~/Applications/PassArc.app and registers the extension.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/scripts"
APP="$OUT/PassArc.app"
APPEX="$APP/Contents/PlugIns/PassArcFinder.appex"
LIB="$OUT/lib"
TARGET="arm64-apple-macos15.0"
SWIFTC=(xcrun swiftc -parse-as-library -swift-version 6 -target "$TARGET" -O)

command rm -rf "$OUT"
mkdir -p "$LIB" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

echo "==> PassArcCore (static library)"
# The extension links it too, so allow only extension-safe APIs
"${SWIFTC[@]}" -application-extension -module-name PassArcCore -emit-library -static \
  -emit-module -emit-module-path "$LIB/PassArcCore.swiftmodule" \
  -o "$LIB/libPassArcCore.a" "$ROOT"/Core/Sources/PassArcCore/*.swift

echo "==> PassArc (app)"
"${SWIFTC[@]}" -module-name PassArc -I "$LIB" -L "$LIB" -lPassArcCore \
  -o "$APP/Contents/MacOS/PassArc" "$ROOT"/App/*.swift
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/Resources/PassArc.icns" "$APP/Contents/Resources/PassArc.icns"
printf 'APPL????' >"$APP/Contents/PkgInfo"

echo "==> PassArcFinder (Finder Sync extension)"
# App extensions start in Foundation's NSExtensionMain
"${SWIFTC[@]}" -application-extension -module-name PassArcFinder -I "$LIB" -L "$LIB" -lPassArcCore \
  -framework FinderSync -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/PassArcFinder" "$ROOT"/Extension/FinderSync.swift
cp "$ROOT/Extension/Info.plist" "$APPEX/Contents/Info.plist"

if [[ -n "${PASSARC_BUILD_VERSION:-}" ]]; then
  for bundle in "$APP" "$APPEX"; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PASSARC_BUILD_VERSION" "$bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PASSARC_BUILD_VERSION" "$bundle/Contents/Info.plist"
  done
fi

IDENTITY="${PASSARC_SIGNING_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" == "-" ]]; then
  SIGN_ARGS+=(--timestamp=none)
else
  SIGN_ARGS+=(--options runtime --timestamp)
fi
echo "==> Signing (inside first)"
codesign "${SIGN_ARGS[@]}" --entitlements "$ROOT/Extension/Extension.entitlements" "$APPEX"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/PassArc.app"
  echo "==> Installing to $DEST"
  pkill -x PassArc 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  command rm -rf "$DEST"
  ditto "$APP" "$DEST"
  LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  # If the copy in build/ stays registered for passarc://, URLs may go there instead
  "$LSR" -u "$APP" 2>/dev/null || true
  "$LSR" -f "$DEST"
  pluginkit -a "$DEST/Contents/PlugIns/PassArcFinder.appex"
  pluginkit -e use -i local.passarc.app.finder || true
  pluginkit -mAv -p com.apple.FinderSync
fi
echo "==> Done: $APP"
