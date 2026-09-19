#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product szElectricityMeter
APP="dist/szElectricityMeter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/szElectricityMeter "$APP/Contents/MacOS/szElectricityMeter"
xcrun strip -S "$APP/Contents/MacOS/szElectricityMeter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
    swift Scripts/make-icon.swift
    iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier cn.shenzhenmeter.app "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"
