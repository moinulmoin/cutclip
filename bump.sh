#!/bin/bash

# Simple version bump script for CutClip
# Usage: ./bump.sh <version>
# Example: ./bump.sh 1.2.0

set -e

# Check if version provided
if [ -z "$1" ]; then
    echo "Usage: ./bump.sh <version>"
    echo "Example: ./bump.sh 1.2.0"
    exit 1
fi

VERSION=$1
BUILD=$(git rev-list HEAD --count)

echo "🔄 Updating CutClip version..."

# Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" cutclip/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" cutclip/Info.plist

# Also update in project file if MARKETING_VERSION is used
if grep -q "MARKETING_VERSION" cutclip.xcodeproj/project.pbxproj; then
    sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION;/g" cutclip.xcodeproj/project.pbxproj
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $BUILD;/g" cutclip.xcodeproj/project.pbxproj
fi

echo "✅ Version: $VERSION"
echo "✅ Build: $BUILD"
echo ""
echo "Next steps:"
echo "1. git add . && git commit -m \"Release v$VERSION\""
echo "2. git tag v$VERSION"
echo "3. git push && git push --tags"
echo "4. ./build-release.sh"
echo "5. gh release create v$VERSION --generate-notes CutClip-$VERSION.dmg"