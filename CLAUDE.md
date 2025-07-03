# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CutClip is a macOS SwiftUI application for clipping YouTube videos. It features a freemium model with 3 free credits per device and license-based unlimited usage. The app automatically downloads required binaries (yt-dlp and FFmpeg) and integrates with a backend API for license validation and usage tracking.

## Build Commands

### Development
```bash
# Build and run in Xcode (recommended for development)
open cutclip.xcodeproj

# Build from command line (development certificate)
xcodebuild -project cutclip.xcodeproj -scheme cutclip -configuration Debug build
```

### Release Distribution (Manual Process - Preferred)
The automated build script can have signing conflicts. Use this manual process instead:

```bash
# Build with distribution certificate
xcodebuild -project cutclip.xcodeproj -scheme cutclip -configuration Release -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application: Ideaplexa LLC (53P98M92V7)" clean build

# Re-sign with secure timestamp for notarization (if needed)
codesign --force --deep --timestamp --options=runtime --sign "Developer ID Application: Ideaplexa LLC (53P98M92V7)" build/Build/Products/Release/cutclip.app

# Create DMG (requires: brew install create-dmg)
create-dmg --volname "CutClip" --window-size 600 400 --icon-size 100 --app-drop-link 450 150 CutClip.dmg build/Build/Products/Release/cutclip.app

# Notarize (use correct keychain profile name)
xcrun notarytool submit CutClip.dmg --keychain-profile "CUTCLIP_NOTARY" --wait

# Staple notarization ticket to DMG
xcrun stapler staple CutClip.dmg
```

### Clean App State (for testing)
```bash
rm -rf ~/Library/Application\ Support/CutClip
defaults delete com.ideaplexa.cutclip
rm -rf ~/Library/Caches/com.ideaplexa.cutclip
rm -rf ~/Library/Containers/com.ideaplexa.cutclip
rm -rf ~/Library/Saved\ Application\ State/com.ideaplexa.cutclip.savedState
killall cutclip 2>/dev/null || true
```

## Architecture

### App Flow
The app follows a strict onboarding sequence managed by `ContentView`:
1. **Disclaimer** (`DisclaimerView`) - Legal notice, saves to `@AppStorage("disclaimerAccepted")`
2. **Auto Setup** (`AutoSetupView`) - Downloads yt-dlp and FFmpeg binaries via `AutoSetupService`
3. **License Setup** (`LicenseStatusView`) - Handles free credits vs license activation
4. **Main App** (`CleanClipperView`) - Video clipping interface with modern UI

### Core Services Architecture

The app follows a clean architecture with services decomposed by responsibility:

**State Management**: `AppCoordinator` manages app flow transitions and provides unified environment object injection.

**License & Usage**: `LicenseManager` and `UsageTracker` coordinate license validation and API communication, delegating to specialized services for caching, networking, and state management.

**Video Processing**: `ClipService` orchestrates the clipping pipeline, coordinating binary management, video downloads, and FFmpeg processing.

**Process Execution**: All external process calls go through `ProcessExecutor` for consistent async/await handling and security.

### Environment Configuration
```bash
# API endpoint (defaults to production URL)
export CUTCLIP_API_BASE_URL="https://cutclip.moinulmoin.com/api"
```

### Design System
The app uses **CleanDS (CleanDesignSystem)** as the primary design system with:
- **Window Size**: 500×450px (main windows), 420×450px (modals)
- **Padding**: 40px standard, 24px for modals
- **Corner Radius**: 8px for UI elements, 16px for window backgrounds
- **Colors**: Black theme throughout with modern UI components
- **Materials**: `.regularMaterial` for window backgrounds
- **Components**: Custom button styles (CleanPrimaryButton, CleanSecondaryButton, CleanLinkButton)

### Dependencies
- **create-dmg**: DMG creation tool (Homebrew) - For creating distribution DMG files
- **yt-dlp & FFmpeg**: Downloaded automatically by `AutoSetupService` during app setup

## Backend Integration

The app integrates with a REST API for license management and usage tracking. Key endpoints:

- `GET /users/check-device` - Check device registration and credit status
- `POST /users/create-device` - Register new device with 3 free credits
- `PUT /users/update-device` - Update device information
- `PUT /users/decrement-free-credits` - Decrement credits after successful clip
- `POST /validate-license` - Validate and activate license key

## Key Implementation Notes

**API Communication**: All backend calls go through a layered architecture with automatic retry logic and error handling.

**Process Security**: External binaries (yt-dlp, FFmpeg) run in a restricted environment for security.

**Video Download**: yt-dlp requires specific format strings and FFmpeg location when running with restricted PATH. The app handles quality selection and video+audio merging automatically.

### Data Flow
- **Device ID**: Hardware UUID → SHA256 → `UserDefaults` cache.
- **License**: API → Keychain storage (`SecureStorage`) → `LicenseManager` state.
- **Binaries**: Auto-download → `~/Library/Application Support/CutClip/bin/`.

## Features

### Video Processing
- **Quality Selection**: Supports 720p, 1080p, 1440p, and 2160p video quality options
- **Aspect Ratios**: Original, 9:16 (vertical), 1:1 (square), and 4:3 cropping options
- **Video Preview**: Loads video metadata before download showing title, duration, thumbnail
- **Time-based Clipping**: Precise start/end time selection in HH:MM:SS format

## File Organization

- **Views**: UI components including onboarding flow and main clipping interface
- **Services**: Core business logic following SOLID principles with specialized services for different responsibilities
- **Models**: Data structures for video processing and app state
- **Utilities**: Helper classes for security, networking, and validation