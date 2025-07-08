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
# Use last 7 characters of commit hash as build number
BUILD=$(git rev-parse --short HEAD)

echo "🔄 Updating CutClip version..."

# Update in project file (this is where Xcode stores the version)
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION;/g" cutclip.xcodeproj/project.pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $BUILD;/g" cutclip.xcodeproj/project.pbxproj

# Note: The actual Info.plist is generated at build time from these values

echo "✅ Version: $VERSION"
echo "✅ Build: $BUILD"
echo ""
echo "Next steps:"
echo "1. git add . && git commit -m \"Release v$VERSION\""
echo "2. git tag v$VERSION"
echo "3. git push && git push --tags"
echo "4. ./build-release.sh"
echo "5. gh release create v$VERSION --generate-notes CutClip-$VERSION.dmg"