#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Cursor Usage.app"
BINARY="$ROOT/macos/.build/release/CursorUsageMenuBar"

cd "$ROOT/macos"
swift build -c release

# Quit any previous instance
pkill -x CursorUsageMenuBar 2>/dev/null || true
sleep 0.5

# Bundle as a proper menu bar agent (.app) so macOS keeps it alive
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/CursorUsageMenuBar"
chmod +x "$APP/Contents/MacOS/CursorUsageMenuBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>CursorUsageMenuBar</string>
	<key>CFBundleIdentifier</key>
	<string>com.local.cursor-usage-tracker</string>
	<key>CFBundleName</key>
	<string>Cursor Usage</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.10</string>
	<key>CFBundleVersion</key>
	<string>1.0.10</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
</dict>
</plist>
PLIST

"$ROOT/scripts/bundle-app-resources.sh" "$APP"

echo "Launching Cursor Usage (menu bar only, no Dock icon)…"
open -a "$APP"
