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
mkdir -p "$LIB" "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"

echo "==> PassArcCore (static library)"
# The extension links it too, so allow only extension-safe APIs
"${SWIFTC[@]}" -application-extension -module-name PassArcCore -emit-library -static \
  -emit-module -emit-module-path "$LIB/PassArcCore.swiftmodule" \
  -o "$LIB/libPassArcCore.a" "$ROOT"/Core/Sources/PassArcCore/*.swift

echo "==> PassArc (app)"
"${SWIFTC[@]}" -module-name PassArc -I "$LIB" -L "$LIB" -lPassArcCore \
  -o "$APP/Contents/MacOS/PassArc" "$ROOT"/App/*.swift
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' >"$APP/Contents/PkgInfo"

echo "==> PassArcFinder (Finder Sync extension)"
# App extensions start in Foundation's NSExtensionMain
"${SWIFTC[@]}" -application-extension -module-name PassArcFinder -I "$LIB" -L "$LIB" -lPassArcCore \
  -framework FinderSync -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/PassArcFinder" "$ROOT"/Extension/FinderSync.swift
cp "$ROOT/Extension/Info.plist" "$APPEX/Contents/Info.plist"

echo "==> Signing (ad hoc, inside first)"
codesign --force --sign - --entitlements "$ROOT/Extension/Extension.entitlements" --timestamp=none "$APPEX"
codesign --force --sign - --timestamp=none "$APP"
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
