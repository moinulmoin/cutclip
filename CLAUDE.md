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
4. **Main App** (`ClipperView`) - Video clipping interface

### Core Services Architecture

**Singleton Pattern**: All major services use `shared` singletons with `@MainActor` for thread safety.

**BinaryManager**: Manages yt-dlp and FFmpeg binaries in `~/Library/Application Support/CutClip/bin/`. Auto-detects existing installations and handles path management.

**LicenseManager**: Central license and usage coordinator. It's the UI's source of truth for all license and credit-related state. It orchestrates `UsageTracker` to perform backend operations.

**UsageTracker**: The sole service responsible for all backend API communication. It handles device status checks, license validation, and credit management with built-in caching and retry logic.

**ClipService**: Orchestrates video clipping by coordinating `BinaryManager` (binaries), `DownloadService` (yt-dlp), and FFmpeg processing.

### Environment Configuration
```bash
# API endpoint (defaults to production URL)
export CUTCLIP_API_BASE_URL="https://cutclip.moinulmoin.com/api"
```

### Design System
- **Window Size**: 500×450px (main windows), 420×450px (modals)
- **Padding**: 40px standard, 24px for modals
- **Corner Radius**: 8px for UI elements, 16px for window backgrounds
- **Colors**: Black theme throughout
- **Materials**: `.regularMaterial` for window backgrounds

### Dependencies
- **Sparkle**: Auto-update framework (GitHub package) - Currently disabled
- **create-dmg**: DMG creation tool (Homebrew)
- **yt-dlp & FFmpeg**: Downloaded automatically by `AutoSetupService`

## Backend Integration

The app integrates with a REST API for license management and usage tracking. Key endpoints:

- `GET /users/check-device`
- `POST /users/create-device`
- `PUT /users/update-device`
- `PUT /users/decrement-free-credits`
- `POST /validate-license`

See `USER_API_DOCS.md` for complete API documentation and flow diagrams.

## Key Implementation Notes & Patterns

### API Calls
All API calls are consolidated in `UsageTracker.swift` and use a robust pattern with secure networking and automatic retries.

```swift
// In UsageTracker.swift
func someApiCall() async throws -> SomeResponse {
    // ... setup ...
    return try await NetworkRetryHelper.retryOperation {
        let request = APIConfiguration.createRequest(url: url)
        let (data, response) = try await APIConfiguration.performSecureRequest(request)
        // ... handle response and errors ...
        return try JSONDecoder().decode(SomeResponse.self, from: data)
    }
}
```

### Process Management
- **Security**: External processes (`yt-dlp`, `ffmpeg`) are executed with a restricted environment (minimal `PATH`, sandboxed `HOME`) to prevent exploits.
- **Progress Tracking**: `ffmpeg`'s `stderr` output is parsed in real-time to provide accurate, duration-based progress for clipping operations.
- **Temporary Files**: `DownloadService` downloads videos to a temporary directory and schedules cleanup to avoid leaving artifacts.

### Data Flow
- **Device ID**: Hardware UUID → SHA256 → `UserDefaults` cache.
- **License**: API → Keychain storage (`SecureStorage`) → `LicenseManager` state.
- **Binaries**: Auto-download → `~/Library/Application Support/CutClip/bin/`.

## File Organization

**Views**: `DisclaimerView`, `AutoSetupView`, `LicenseStatusView`, `ClipperView` follow the app flow sequence.

**Services**: Business logic in `*Manager.swift` and `*Service.swift` files using singleton pattern.

**Models**: `ClipJob.swift` for video processing data structures.

**Utilities**: `DeviceIdentifier`, `SecureStorage`, `NetworkMonitor`, `ErrorHandler` for cross-cutting concerns.