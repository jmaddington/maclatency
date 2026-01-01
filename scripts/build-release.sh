#!/bin/bash
set -euo pipefail

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

echo "Building MacPing v$VERSION"

# Clean and build
xcodebuild -project MacPing.xcodeproj \
    -scheme MacPing \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build

# Create release directory
mkdir -p release

APP_PATH="build/Build/Products/Release/MacPing.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

# Create ZIP
echo "Creating ZIP archive..."
ditto -c -k --keepParent "$APP_PATH" "release/MacPing-${VERSION}.zip"

# Create DMG using create-dmg
echo "Creating DMG..."
create-dmg \
    --volname "MacPing" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "MacPing.app" 150 190 \
    --hide-extension "MacPing.app" \
    --app-drop-link 450 185 \
    "release/MacPing-${VERSION}.dmg" \
    "$APP_PATH"

echo "Release artifacts created:"
ls -la release/

echo "Done!"
