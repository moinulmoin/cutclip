# CutClip - YouTube Clipper App Development Plan

## 🎯 Refined Plan: Basic YouTube Clipper v1.0

A minimalist macOS app for clipping YouTube videos with a clean, focused interface.

### Project Overview
- **Target**: macOS 14.6+ (Sonoma)
- **Tech Stack**: Swift 5.0 + SwiftUI
- **Dependencies**: User-provided yt-dlp and FFmpeg binaries
- **Distribution**: Direct download with notarization
- **Timeline**: 3 weeks to MVP

---

## Phase 1: Core MVP (3 weeks)
Deliver exactly what's shown in the UI mockup - nothing more.

### Week 1: Foundation & Legal Framework

#### Days 1-2: Fix Critical Issues
1. **Disable App Sandbox**:
   - Remove sandbox from entitlements
   - Add hardened runtime with exceptions
   - Test basic Process() execution

2. **Create Legal Disclaimer**:
   - First-launch disclaimer about user responsibility
   - "Bring your own yt-dlp" approach
   - Store acceptance in UserDefaults

#### Days 3-5: Implement Exact UI from Screenshot
3. **Create ClipperView.swift** matching the design:
   - URL TextField with rounded style
   - Time input fields (00:00:00 format)
   - Ratio dropdown: Original, 16:9, 1:1
   - Circular download button
   - "🔥 N bangers clipped" counter
   - Dark blur background

#### Days 6-7: Binary Management
4. **Implement BinaryManager**:
   - Check for yt-dlp/ffmpeg in ~/Library/Application Support/CutClip/
   - Show setup wizard if missing
   - Let users browse to select binaries
   - Verify binaries work with test command

### Week 2: Core Functionality

#### Days 8-10: Basic Download Pipeline
5. **Create DownloadService**:
   - Validate YouTube URL
   - Execute yt-dlp to download video
   - Parse progress from stderr
   - Handle basic errors only

#### Days 11-12: FFmpeg Integration
6. **Create ClipService**:
   - Trim video between start/end times
   - Apply aspect ratio crop
   - Output to ~/Downloads/
   - Increment banger counter

#### Days 13-14: Polish & Testing
7. **Error Handling**:
   - Network failures
   - Invalid URLs
   - Disk space issues
   - Show user-friendly alerts

### Week 3: Distribution Prep

#### Days 15-17: App Polish
8. **Add Essential Features**:
   - Progress indicator during download/clip
   - Cancel button
   - Basic preferences (output folder)
   - Keyboard shortcuts (Cmd+V to paste URL)

#### Days 18-20: Distribution
9. **Prepare for Release**:
   - Developer ID certificate
   - Notarization workflow
   - Create DMG with background
   - Simple website with disclaimer

#### Day 21: Beta Release
10. **Soft Launch**:
    - Direct download only
    - Clear legal disclaimers
    - Gather feedback

---

## 🏗️ Simplified Architecture

```
CutClip.app/
├── Views/
│   ├── ClipperView.swift         // Main UI
│   ├── SetupWizardView.swift     // Binary setup
│   └── DisclaimerView.swift      // Legal disclaimer
├── Services/
│   ├── BinaryManager.swift       // yt-dlp/ffmpeg management
│   ├── DownloadService.swift     // YouTube download
│   └── ClipService.swift         // Video trimming
├── Models/
│   └── ClipJob.swift            // Simple data model
└── CutClipApp.swift             // App entry point
```

---

## 📋 Implementation Details

### 1. Updated Entitlements
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

### 2. Main UI Component
```swift
struct ClipperView: View {
    @State private var urlText = ""
    @State private var startTime = "00:00:00"
    @State private var endTime = "00:00:10"
    @State private var selectedRatio = "Original"
    @AppStorage("bangersClipped") private var bangersCount = 0

    var body: some View {
        VStack(spacing: 20) {
            // URL Input
            HStack {
                TextField("https://www.youtube.com/watch?v=...", text: $urlText)
                    .textFieldStyle(.roundedBorder)

                Button(action: download) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.largeTitle)
                }
            }

            // Time inputs
            HStack {
                VStack(alignment: .leading) {
                    Text("Start At").font(.caption)
                    TextField("00:00:00", text: $startTime)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("End At").font(.caption)
                    TextField("00:00:10", text: $endTime)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("Ratio").font(.caption)
                    Picker("", selection: $selectedRatio) {
                        Text("Original").tag("Original")
                        Text("16:9").tag("16:9")
                        Text("1:1").tag("1:1")
                    }
                }
            }

            // Status
            Text("🔥 \(bangersCount) bangers clipped")
                .foregroundColor(.orange)
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .frame(width: 600, height: 200)
    }
}
```

### 3. Legal Disclaimer
```swift
struct DisclaimerView: View {
    @AppStorage("disclaimerAccepted") private var accepted = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Important Notice")
                .font(.title)

            Text("""
            This app requires you to provide your own yt-dlp and FFmpeg binaries.

            By using this app, you acknowledge that:
            • You are responsible for compliance with YouTube's Terms of Service
            • You will only download content you have permission to download
            • The developers are not responsible for how you use this tool
            """)
            .multilineTextAlignment(.leading)

            Button("I Understand and Accept") {
                accepted = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 500)
    }
}
```

---

## 🚫 What We're NOT Building (Yet)

Per the requirement to execute *exactly* what's needed:
- ❌ Download queue system
- ❌ Preview thumbnails
- ❌ Multiple quality options
- ❌ Shortcuts integration
- ❌ Advanced error recovery
- ❌ Auto-updates (manual only for v1)

---

## 🎯 Success Metrics for v1.0

- ✅ Matches UI mockup exactly
- ✅ Downloads and clips one video at a time
- ✅ Works with user-provided binaries
- ✅ Saves to ~/Downloads/
- ✅ Increments banger counter
- ✅ Can be notarized and distributed

---

## 🔄 Immediate Next Steps

1. **Update Entitlements** (30 min)
2. **Create Basic UI** (2 hours)
3. **Legal Disclaimer** (1 hour)
4. **Binary Management Setup** (4 hours)
5. **Core Download Pipeline** (8 hours)

---

## 📝 Notes

- **Legal Protection**: "Bring your own binaries" approach shifts responsibility to users
- **Distribution**: Direct download only, not App Store
- **Updates**: Manual distribution for v1.0
- **Support**: Minimal support, clear documentation only

This plan delivers a focused, legally-protected MVP that matches the exact UI requirements in 3 weeks.