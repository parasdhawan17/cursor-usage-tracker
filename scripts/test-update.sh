#!/bin/bash
# Build the app, pretend it's an older version, and launch so the in-app updater offers GitHub latest.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Cursor Usage.app"
FAKE_VERSION="${1:-1.0.7}"

echo "Building Cursor Usage..."
"$ROOT/run-menubar.sh"

pkill -x CursorUsageMenuBar 2>/dev/null || true
sleep 0.5

echo "Setting version to ${FAKE_VERSION} (GitHub latest will show as an update)..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${FAKE_VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${FAKE_VERSION}" "$APP/Contents/Info.plist"

defaults delete com.local.cursor-usage-tracker updateLastCheckAt 2>/dev/null || true

echo "Launching as v${FAKE_VERSION}..."
open -a "$APP"

echo ""
echo "Done. Open the menu bar panel - you should see an update banner."
echo "After testing, restore the real build with: ./run-menubar.sh"
