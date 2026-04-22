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

# Use a stable self-signed identity if available so TCC grants survive rebuilds.
# Set it up once via: bash scripts/setup-codesign.sh
SIGN_IDENTITY="AI Voice Local"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" --entitlements Resources/AIVoice.entitlements "$APP_BUNDLE"
    echo "Signed with: $SIGN_IDENTITY"
else
    codesign --force --sign - --entitlements Resources/AIVoice.entitlements "$APP_BUNDLE"
    echo "Signed ad-hoc (run 'bash scripts/setup-codesign.sh' to make TCC grants survive rebuilds)"
fi

echo ""
echo "Built: $APP_BUNDLE"
echo "Run:   open \"$APP_BUNDLE\""
echo ""
echo "To install: cp -r \"$APP_BUNDLE\" /Applications/"
