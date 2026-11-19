#!/bin/bash
# Renders the dialog to PNG files. Usage: scripts/snapshot.sh <output dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/snapshot"
mkdir -p "$OUT/lib" "$1"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos15.0 -module-name PassArcCore \
  -emit-library -static -emit-module -emit-module-path "$OUT/lib/PassArcCore.swiftmodule" \
  -o "$OUT/lib/libPassArcCore.a" "$ROOT"/Core/Sources/PassArcCore/*.swift
# Leave out AppDelegate.swift (it has @main)
APP_SOURCES=$(ls "$ROOT"/App/*.swift | grep -v AppDelegate.swift)
xcrun swiftc -swift-version 6 -target arm64-apple-macos15.0 -module-name Snapshot -I "$OUT/lib" -L "$OUT/lib" \
  -lPassArcCore -o "$OUT/snapshot" $APP_SOURCES "$ROOT/scripts/snapshot/main.swift"
"$OUT/snapshot" "$1"
