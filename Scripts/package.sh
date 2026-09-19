#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP='dist/szElectricityMeter.app'
./Scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(uname -m)
DMG="dist/szElectricityMeter-${VERSION}-${ARCH}.dmg"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/szelectricitymeter-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/szElectricityMeter.app"
ln -s /Applications "$STAGE/Applications"
cp docs/安装说明.txt "$STAGE/安装说明.txt"
hdiutil create -volname 'szElectricityMeter' -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
