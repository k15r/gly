#!/usr/bin/env bash
# Build gly.app (with the embedded agent) for local use.
# Usage: scripts/build.sh [Debug|Release]   -> build/Build/Products/<config>/gly.app
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

xcodebuild \
  -project gly.xcodeproj \
  -scheme gly \
  -configuration "$CONFIG" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=DB33H6YGK7 \
  build | grep -E "error:|warning:.*(sign|entitle|provision)|BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/$CONFIG/gly.app"
test -d "$APP" || { echo "build failed: $APP missing" >&2; exit 1; }
test -x "$APP/Contents/MacOS/glyAgent" || { echo "agent missing in bundle" >&2; exit 1; }
test -x "$APP/Contents/MacOS/gly-mcp" || { echo "gly-mcp missing in bundle" >&2; exit 1; }
test -f "$APP/Contents/Library/LaunchAgents/dev.k15r.gly.store-agent.plist" || { echo "launch agent plist missing" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
echo "OK: $APP"
