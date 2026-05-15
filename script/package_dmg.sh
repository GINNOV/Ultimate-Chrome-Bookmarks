#!/usr/bin/env bash
set -euo pipefail

APP_NAME="UltimateOrganizer"
VOLUME_NAME="Ultimate Organizer"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
DMG_ROOT="$DIST_DIR/dmg-root"
README_SOURCE="$ROOT_DIR/docs/DMG-Quick-Start.txt"

cd "$ROOT_DIR"

./script/build_and_run.sh --build-only

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
DMG_NAME="$APP_NAME-$VERSION-build-$BUILD.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

rm -rf "$DMG_ROOT"
rm -f "$DMG_PATH"
mkdir -p "$DMG_ROOT"

cp -R "$APP_BUNDLE" "$DMG_ROOT/"
cp "$README_SOURCE" "$DMG_ROOT/Quick Start.txt"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_ROOT"

echo "$DMG_PATH"
