# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CutClip is a minimalist macOS YouTube clipper app built with SwiftUI targeting macOS 14.6+ (Sonoma). The app allows users to download YouTube videos and clip specific time segments with aspect ratio control.

## Architecture

Based on plan.md, the app follows this structure:

```
cutclip/
├── Views/
│   ├── ClipperView.swift         // Main UI matching exact mockup design
│   ├── SetupWizardView.swift     // Binary setup wizard
│   └── DisclaimerView.swift      // Legal disclaimer (first launch)
├── Services/
│   ├── BinaryManager.swift       // yt-dlp/ffmpeg management
│   ├── DownloadService.swift     // YouTube download pipeline
│   └── ClipService.swift         // Video trimming with FFmpeg
├── Models/
│   └── ClipJob.swift            // Data model for clip operations
└── cutclipApp.swift             // App entry point
```

## Development Commands

This is a standard Xcode project. Build and run using:
- **Build**: Cmd+B in Xcode or `xcodebuild build`
- **Run**: Cmd+R in Xcode
- **Clean**: Cmd+Shift+K in Xcode

## Key Implementation Notes

### Entitlements Configuration
The app requires specific entitlements to execute external binaries (yt-dlp/FFmpeg):
- App Sandbox must be **disabled** (`<false/>`)
- Hardened runtime exceptions needed for unsigned executable memory
- File access permissions for user-selected files

### Legal Strategy
- "Bring your own binaries" approach - users provide yt-dlp/FFmpeg
- First-launch disclaimer shifts responsibility to users
- No bundled download tools to avoid legal issues

### Binary Management
- Binaries stored in `~/Library/Application Support/CutClip/`
- Setup wizard guides users to locate/install required tools
- Binary verification with test commands before use

### Core Workflow
1. User pastes YouTube URL
2. Sets start/end times (HH:MM:SS format)
3. Selects aspect ratio (Original, 16:9, 1:1)
4. Downloads video via yt-dlp
5. Clips segment via FFmpeg
6. Saves to ~/Downloads/
7. Increments "bangers clipped" counter

## Current State

Fresh Xcode project with default SwiftUI template. App is currently sandboxed and needs entitlements update as first implementation step per plan.md Phase 1.