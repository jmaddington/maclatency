#!/bin/bash
set -euo pipefail

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

echo "Setting version to $VERSION"

# Update MARKETING_VERSION in project.pbxproj
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" MacPing.xcodeproj/project.pbxproj

# Update CURRENT_PROJECT_VERSION (build number) - use version without dots
BUILD_NUMBER=$(echo "$VERSION" | tr -d '.')
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" MacPing.xcodeproj/project.pbxproj

echo "Version set to $VERSION (build $BUILD_NUMBER)"
