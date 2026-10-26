#!/usr/bin/env bash
# Build WorkDash.app (with the embedded agent) for local use.
# Usage: scripts/build.sh [Debug|Release]   -> build/Build/Products/<config>/WorkDash.app
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

xcodebuild \
  -project WorkDash.xcodeproj \
  -scheme WorkDash \
  -configuration "$CONFIG" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=DB33H6YGK7 \
  build | grep -E "error:|warning:.*(sign|entitle|provision)|BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/$CONFIG/WorkDash.app"
test -d "$APP" || { echo "build failed: $APP missing" >&2; exit 1; }
test -x "$APP/Contents/MacOS/WorkDashAgent" || { echo "agent missing in bundle" >&2; exit 1; }
test -f "$APP/Contents/Library/LaunchAgents/dev.k15r.workdash.store-agent.plist" || { echo "launch agent plist missing" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
echo "OK: $APP"
