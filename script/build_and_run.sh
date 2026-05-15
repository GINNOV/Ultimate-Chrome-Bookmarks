#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="UltimateOrganizer"
BUNDLE_ID="com.littlethings.UltimateOrganizer"
MARKETING_VERSION="0.1.0"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
BUILD_NUMBER_FILE="$ROOT_DIR/build-number.txt"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://ginnov.github.io/Ultimate-Chrome-Bookmarks/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-7/gJsLw/VpKZOw9US3FRxwT24JNPdgwxd1ioEcisj+g=}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ -n "${CURRENT_PROJECT_VERSION:-}" ]]; then
  BUILD_NUMBER="$CURRENT_PROJECT_VERSION"
elif [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
  BUILD_NUMBER="$GITHUB_RUN_NUMBER"
else
  CURRENT_BUILD_NUMBER="0"
  if [[ -f "$BUILD_NUMBER_FILE" ]]; then
    CURRENT_BUILD_NUMBER="$(tr -dc '0-9' < "$BUILD_NUMBER_FILE")"
    CURRENT_BUILD_NUMBER="${CURRENT_BUILD_NUMBER:-0}"
  fi
  BUILD_NUMBER="$((CURRENT_BUILD_NUMBER + 1))"
  printf '%s\n' "$BUILD_NUMBER" > "$BUILD_NUMBER_FILE"
fi

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -path "*/Sparkle.framework" -type d -prune | head -n 1 || true)"
if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoadsInWebContent</key>
    <true/>
  </dict>
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUUpdateCheckInterval</key>
  <integer>3600</integer>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
