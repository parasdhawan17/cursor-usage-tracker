#!/bin/bash
# Build Cursor Usage.app (Universal: Apple Silicon + Intel) and package as DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Cursor Usage.app"
MACOS="$ROOT/macos"
ARM_BIN="$MACOS/.build/arm64/release/CursorUsageMenuBar"
X64_BIN="$MACOS/.build/x86_64/release/CursorUsageMenuBar"
UNIVERSAL_BIN="$MACOS/.build/universal/CursorUsageMenuBar"
DIST="$ROOT/dist"
DMG_NAME="Cursor-Usage-1.0.10-universal.dmg"
DMG_PATH="$DIST/$DMG_NAME"
VERSION="1.0.10"

echo "Building arm64..."
swift build -c release --package-path "$MACOS" --build-path "$MACOS/.build/arm64" --triple arm64-apple-macosx13.0

echo "Building x86_64 (Intel Macs)..."
swift build -c release --package-path "$MACOS" --build-path "$MACOS/.build/x86_64" --triple x86_64-apple-macosx13.0

mkdir -p "$MACOS/.build/universal"
lipo -create -output "$UNIVERSAL_BIN" "$ARM_BIN" "$X64_BIN"
lipo -info "$UNIVERSAL_BIN"

echo "Bundling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$UNIVERSAL_BIN" "$APP/Contents/MacOS/CursorUsageMenuBar"
chmod +x "$APP/Contents/MacOS/CursorUsageMenuBar"

cat > "$APP/Contents/Info.plist" <<PLIST
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
	<key>CFBundleDisplayName</key>
	<string>Cursor Usage</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

"$ROOT/scripts/bundle-app-resources.sh" "$APP"

if command -v codesign >/dev/null; then
  echo "Signing app (ad-hoc)..."
  codesign --force --sign - "$APP"
  codesign --verify --deep --strict "$APP"
fi

echo "Creating DMG..."
rm -rf "$DIST/dmg-staging" "$DMG_PATH"
mkdir -p "$DIST/dmg-staging"
cp -R "$APP" "$DIST/dmg-staging/"
ln -s /Applications "$DIST/dmg-staging/Applications"
# Avoid Gatekeeper quarantine issues when the DMG is built locally.
xattr -cr "$DIST/dmg-staging/Cursor Usage.app" 2>/dev/null || true
mkdir -p "$DIST"
hdiutil create \
  -volname "Cursor Usage" \
  -srcfolder "$DIST/dmg-staging" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
rm -rf "$DIST/dmg-staging"

echo ""
echo "Done: $DMG_PATH"
echo "Universal build (Apple Silicon + Intel), macOS 13+."
echo "Install: open DMG → drag to Applications → first launch: Right-click app → Open if blocked."
echo "The app runs in the menu bar only (gear icon). It does not open a regular window."
