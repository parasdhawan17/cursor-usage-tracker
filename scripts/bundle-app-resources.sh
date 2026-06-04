#!/bin/bash
# Copy app icon into a .app bundle and ensure Info.plist references it.
set -euo pipefail

APP="${1:?Usage: bundle-app-resources.sh /path/to/App.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICNS="$ROOT/AppIcon/CursorUsage.icns"

if [[ ! -f "$ICNS" ]]; then
  "$ROOT/scripts/build-app-icon.sh"
fi

mkdir -p "$APP/Contents/Resources"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
