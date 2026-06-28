#!/bin/bash
# Build DMG (if missing) and publish a GitHub release with the asset attached.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.10}"
TAG="v${VERSION}"
DMG="$ROOT/dist/Cursor-Usage-${VERSION}-universal.dmg"

if ! command -v gh >/dev/null; then
  echo "GitHub CLI (gh) is required. Install: https://cli.github.com/" >&2
  echo "Then run: gh auth login" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Not logged into GitHub. Run: gh auth login" >&2
  exit 1
fi

if [[ ! -f "$DMG" ]]; then
  echo "DMG not found — building..."
  "$ROOT/build-dmg.sh"
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Creating tag $TAG..."
  git tag -a "$TAG" -m "Cursor Usage ${VERSION}"
  git push origin "$TAG"
fi

NOTES="$(cat <<EOF
## Cursor Usage ${VERSION}

In-app updates: the menu bar app now checks GitHub for new releases and installs them with one click.

### What is new
- Check GitHub Releases every 6 hours for a newer version
- Show a compact update banner in the usage panel when an update is available
- Download the universal DMG and replace the app in Applications automatically
- Add \`AppVersion\` helpers for semver comparison against release tags

### Install
1. Download **Cursor-Usage-${VERSION}-universal.dmg** below
2. Open the DMG and drag **Cursor Usage** to **Applications**
3. First launch: right-click the app → **Open** (if Gatekeeper blocks it)
4. Click the gear icon in the menu bar and paste your WorkosCursorSessionToken

See the [README](https://github.com/parasdhawan17/cursor-usage-tracker#quick-start-menu-bar-app) for full setup instructions.
EOF
)"

echo "Publishing release $TAG..."
gh release create "$TAG" \
  --repo parasdhawan17/cursor-usage-tracker \
  --title "Cursor Usage ${VERSION}" \
  --notes "$NOTES" \
  "$DMG"

echo "Done: https://github.com/parasdhawan17/cursor-usage-tracker/releases/tag/${TAG}"
