#!/bin/bash
set -e

BINARY_NAME="AIVoice"
APP_NAME="AI Voice"
APP_BUNDLE="$APP_NAME.app"
BUNDLE_ID="com.romantools.aivoice"

echo "Building $APP_NAME..."

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$BINARY_NAME" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/"

codesign --force --sign - --entitlements Resources/AIVoice.entitlements "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Run:   open \"$APP_BUNDLE\""
echo ""
echo "To install: cp -r \"$APP_BUNDLE\" /Applications/"

# Reset stale Accessibility grant so the app re-prompts with fresh CDHash
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
