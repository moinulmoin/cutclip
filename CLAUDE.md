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
# 1. Build with distribution certificate
xcodebuild -project cutclip.xcodeproj -scheme cutclip -configuration Release -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application: Ideaplexa LLC (53P98M92V7)" clean build

# 2. Create DMG (requires: brew install create-dmg)
create-dmg --volname "CutClip" --window-size 600 400 --icon-size 100 --app-drop-link 450 150 CutClip.dmg build/Build/Products/Release/cutclip.app

# 3. Notarize (requires notarization keychain profile setup)
xcrun notarytool submit CutClip.dmg --keychain-profile "notarization" --wait

# 4. Staple notarization
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
4. **Main App** (`ClipperView`) - Video clipping interface

### Core Services Architecture

**Singleton Pattern**: All major services use `shared` singletons with `@MainActor` for thread safety.

**BinaryManager**: Manages yt-dlp and FFmpeg binaries in `~/Library/Application Support/CutClip/bin/`. Auto-detects existing installations and handles path management.

**LicenseManager**: Central license and usage coordination. Integrates with `UsageTracker`, `DeviceRegistrationService`, and backend API. Determines `needsLicenseSetup` state.

**UsageTracker**: Manages free credits (3 per device) and usage tracking. Communicates with backend API for credit decrements and device registration.

**DeviceRegistrationService**: Handles device registration and license validation with backend API. See `USER_API_DOCS.md` for complete API reference.

**ClipService**: Orchestrates video clipping by coordinating `BinaryManager` (binaries), `DownloadService` (yt-dlp), and FFmpeg processing.

**UpdateManager**: Sparkle auto-update integration. Currently disabled for v1.0 (`startingUpdater: false`). Enable in v1.1 by changing to `true` and uncommenting update UI.

### Environment Configuration
```bash
# API endpoint (defaults to localhost:3000)
export CUTCLIP_API_BASE_URL="https://your-api-domain.com"
```

### Design System
- **Window Size**: 500×450px (main windows), 440×400px (modals)
- **Padding**: 40px standard, 24px for modals
- **Corner Radius**: 8px for UI elements, 16px for window backgrounds
- **Colors**: Black theme throughout (no purple gradients)
- **Materials**: `.regularMaterial` for window backgrounds

### Dependencies
- **Sparkle**: Auto-update framework (GitHub package)
- **create-dmg**: DMG creation tool (Homebrew)
- **yt-dlp & FFmpeg**: Downloaded automatically by `AutoSetupService`

## Backend Integration

The app integrates with a REST API for license management and usage tracking. Key endpoints:

- `GET /api/users/check-device` - Check device registration status
- `POST /api/users/create-device` - Register new device
- `GET /api/validate-license` - Validate license key
- `PUT /api/users/update-device` - Link device to license
- `PUT /api/users/decrement-free-credits` - Use free credit

See `USER_API_DOCS.md` for complete API documentation and flow diagrams.

## File Organization

**Views**: `DisclaimerView`, `AutoSetupView`, `LicenseStatusView`, `ClipperView` follow the app flow sequence.

**Services**: Business logic in `*Manager.swift` and `*Service.swift` files using singleton pattern.

**Models**: `ClipJob.swift` for video processing data structures.

**Utilities**: `DeviceIdentifier`, `SecureStorage`, `NetworkMonitor`, `ErrorHandler` for cross-cutting concerns.

## Key Implementation Notes

- All UI uses consistent sizing (500×450px) with ScrollView for overflow
- Environment objects are passed down from `ContentView` to child views
- Binary downloads are handled automatically with user-friendly progress messages
- License validation happens before device linking to prevent conflicts
- App state is managed through Published properties and @AppStorage for persistence