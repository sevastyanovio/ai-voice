#!/bin/bash
set -e

APP_NAME="VoiceNote"
APP_BUNDLE="$APP_NAME.app"

echo "Building $APP_NAME..."

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$APP_BUNDLE/Contents/"

codesign --force --sign - --entitlements Resources/VoiceNote.entitlements "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Run:   open $APP_BUNDLE"
echo ""
echo "To install: cp -r $APP_BUNDLE /Applications/"

# Reset stale Accessibility grant so the app re-prompts with fresh CDHash
tccutil reset Accessibility com.romantools.voicenote 2>/dev/null || true
