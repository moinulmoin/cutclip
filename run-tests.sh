#!/bin/bash
#
# Test runner script for CutClip
# Runs all tests and generates coverage report
#

set -e

echo "🧪 Running CutClip Tests..."
echo "=========================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clean previous test results
echo "🧹 Cleaning previous test results..."
rm -rf .build/test-results
rm -rf coverage

# Run tests with coverage
echo -e "\n📊 Running tests with coverage..."
xcodebuild test \
    -project cutclip.xcodeproj \
    -scheme cutclip \
    -destination 'platform=macOS' \
    -enableCodeCoverage YES \
    -resultBundlePath .build/test-results \
    2>&1 | xcpretty

# Check if tests passed
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo -e "\n${GREEN}✅ All tests passed!${NC}"
else
    echo -e "\n${RED}❌ Tests failed!${NC}"
    exit 1
fi

# Generate coverage report
echo -e "\n📈 Generating coverage report..."
xcrun xccov view --report --json .build/test-results.xcresult > coverage.json

# Parse coverage and display summary
if command -v python3 &> /dev/null; then
    python3 - <<EOF
import json
import sys

with open('coverage.json', 'r') as f:
    data = json.load(f)

total_coverage = 0
file_count = 0

print("\n📊 Coverage Summary:")
print("=" * 50)

for target in data.get('targets', []):
    if 'cutclip' in target.get('name', ''):
        for file in target.get('files', []):
            if file['path'].endswith('.swift') and 'Tests' not in file['path']:
                coverage = file.get('lineCoverage', 0) * 100
                total_coverage += coverage
                file_count += 1
                
                # Color code based on coverage
                if coverage >= 80:
                    color = '\033[0;32m'  # Green
                elif coverage >= 60:
                    color = '\033[1;33m'  # Yellow
                else:
                    color = '\033[0;31m'  # Red
                
                filename = file['path'].split('/')[-1]
                print(f"{color}{filename:30} {coverage:6.2f}%\033[0m")

if file_count > 0:
    avg_coverage = total_coverage / file_count
    print("=" * 50)
    
    if avg_coverage >= 80:
        color = '\033[0;32m'  # Green
    elif avg_coverage >= 60:
        color = '\033[1;33m'  # Yellow
    else:
        color = '\033[0;31m'  # Red
    
    print(f"{color}Average Coverage: {avg_coverage:.2f}%\033[0m")
EOF
fi

# Run specific test suites if requested
if [ "$1" == "--unit" ]; then
    echo -e "\n🔬 Running unit tests only..."
    xcodebuild test \
        -project cutclip.xcodeproj \
        -scheme cutclip \
        -destination 'platform=macOS' \
        -only-testing:cutclipTests/Services \
        2>&1 | xcpretty
elif [ "$1" == "--integration" ]; then
    echo -e "\n🔗 Running integration tests only..."
    xcodebuild test \
        -project cutclip.xcodeproj \
        -scheme cutclip \
        -destination 'platform=macOS' \
        -only-testing:cutclipTests/Integration \
        2>&1 | xcpretty
elif [ "$1" == "--watch" ]; then
    echo -e "\n👁️  Watching for changes..."
    echo "Press Ctrl+C to stop"
    
    # Use fswatch if available
    if command -v fswatch &> /dev/null; then
        fswatch -o cutclip cutclipTests | while read; do
            clear
            echo "🔄 Changes detected, running tests..."
            $0
        done
    else
        echo -e "${YELLOW}⚠️  fswatch not found. Install with: brew install fswatch${NC}"
        exit 1
    fi
fi

echo -e "\n✨ Test run complete!"

# Optional: Open coverage report in browser
if [ "$2" == "--open-coverage" ]; then
    echo "📂 Opening coverage report..."
    open .build/test-results.xcresult
fi