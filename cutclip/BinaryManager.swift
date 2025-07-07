//
//  BinaryManager.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

@MainActor
class BinaryManager: ObservableObject, Sendable {
    @Published var ytDlpPath: String?
    @Published var ffmpegPath: String?
    @Published var isConfigured: Bool = false
    @Published var errorMessage: String?
    @Published var isVerifying: Bool = false

    private let appSupportDirectory: URL

    // Task management
    private var verificationTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    private var hasWarmedUp = false
    private var hasCheckedBinaries = false

    nonisolated init() {
        // Create app support directory with graceful error handling
        let fileManager = FileManager.default
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CutClip")
        
        if let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportDir = supportDir.appendingPathComponent("CutClip")
            
            // Create directory if it doesn't exist
            do {
                try fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
                appSupportDirectory = appSupportDir
            } catch {
                print("❌ Failed to create app support directory: \(error)")
                // Fall back to temp directory
                appSupportDirectory = tempDir
                try? fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            }
        } else {
            print("❌ Unable to access Application Support directory, using temp directory")
            // Fall back to temp directory
            appSupportDirectory = tempDir
            try? fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        }

        // Don't check binaries on init - wait for first use
        // This prevents unnecessary warm-up on every app launch
    }

    var ytDlpURL: URL? {
        guard let path = ytDlpPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var ffmpegURL: URL? {
        guard let path = ffmpegPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    func checkBinaries() {
        // Check in bin subdirectory (auto-downloaded location)
        let binDirectory = appSupportDirectory.appendingPathComponent("bin")
        let ytDlpFile = binDirectory.appendingPathComponent("yt-dlp")
        let ffmpegFile = binDirectory.appendingPathComponent("ffmpeg")

        if FileManager.default.fileExists(atPath: ytDlpFile.path) {
            ytDlpPath = ytDlpFile.path
        }

        if FileManager.default.fileExists(atPath: ffmpegFile.path) {
            ffmpegPath = ffmpegFile.path
        }

        updateConfigurationStatus()
        // Don't auto-verify or warm up - use lazy initialization instead
    }
    
    nonisolated func checkBinariesAsync() async {
        // Do file checks off main thread
        let binDirectory = appSupportDirectory.appendingPathComponent("bin")
        let ytDlpFile = binDirectory.appendingPathComponent("yt-dlp")
        let ffmpegFile = binDirectory.appendingPathComponent("ffmpeg")
        
        let ytDlpExists = FileManager.default.fileExists(atPath: ytDlpFile.path)
        let ffmpegExists = FileManager.default.fileExists(atPath: ffmpegFile.path)
        
        // Update paths on main thread
        await MainActor.run {
            if ytDlpExists {
                self.ytDlpPath = ytDlpFile.path
            }
            if ffmpegExists {
                self.ffmpegPath = ffmpegFile.path
            }
            self.updateConfigurationStatus()
            // Don't auto-verify or warm up - wait for first use
        }
    }

    func setBinaryPath(for binary: BinaryType, path: String) {
        switch binary {
        case .ytDlp:
            ytDlpPath = path
        case .ffmpeg:
            ffmpegPath = path
        }
        updateConfigurationStatus()
    }
    
    /// Set binary path without triggering automatic verification
    /// Used when the binary has already been verified externally
    func setBinaryPathVerified(for binary: BinaryType, path: String) {
        switch binary {
        case .ytDlp:
            ytDlpPath = path
        case .ffmpeg:
            ffmpegPath = path
        }
        // Don't trigger automatic verification since binary is pre-verified
        // But do update configuration status
        updateConfigurationStatus()
    }

    nonisolated func verifyBinary(_ binary: BinaryType) async -> Bool {
        let (path, testArgs) = await MainActor.run {
            switch binary {
            case .ytDlp:
                return (self.ytDlpPath, ["--version"])
            case .ffmpeg:
                return (self.ffmpegPath, ["-version"])
            }
        }

        guard let binaryPath = path else { return false }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = testArgs
            
            // Secure process environment - restrict PATH and environment
            process.environment = [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ]

            do {
                try process.run()
                
                // Use async notification instead of blocking waitUntilExit
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus == 0)
                }
            } catch {
                print("❌ Failed to verify \(binary.displayName): \(error)")
                continuation.resume(returning: false)
                return
            }
        }
    }

    nonisolated func verifyAllBinaries() async -> Bool {
        let ytDlpValid = await verifyBinary(.ytDlp)
        let ffmpegValid = await verifyBinary(.ffmpeg)
        return ytDlpValid && ffmpegValid
    }

    /// Verify binaries with user feedback
    func verifyBinariesWithFeedback() async {
        isVerifying = true
        errorMessage = nil

        defer {
            isVerifying = false
        }

        let ytDlpValid = await verifyBinary(.ytDlp)
        let ffmpegValid = await verifyBinary(.ffmpeg)

        if !ytDlpValid {
            errorMessage = "yt-dlp verification failed. The binary may be corrupted or incompatible."
            isConfigured = false
            print("❌ yt-dlp verification failed")
            return
        }

        if !ffmpegValid {
            errorMessage = "FFmpeg verification failed. The binary may be corrupted or incompatible."
            isConfigured = false
            print("❌ FFmpeg verification failed")
            return
        }

        print("✅ All binaries verified successfully")
        isConfigured = true
    }

    private func updateConfigurationStatus() {
        let hasAllBinaries = ytDlpPath != nil && ffmpegPath != nil
        
        print("🔧 BinaryManager.updateConfigurationStatus:")
        print("  - ytDlpPath: \(ytDlpPath ?? "nil")")
        print("  - ffmpegPath: \(ffmpegPath ?? "nil")")
        print("  - errorMessage: \(errorMessage ?? "nil")")
        print("  - hasAllBinaries: \(hasAllBinaries)")

        // Only set as configured if we have all binaries and no error
        if hasAllBinaries && errorMessage == nil {
            isConfigured = true
            print("  ✅ Setting isConfigured = true")
        } else {
            isConfigured = false
            print("  ❌ Setting isConfigured = false")
        }
    }
    
    /// Mark binaries as configured without additional verification
    /// Used when binaries have already been verified by AutoSetupService
    func markAsConfigured() {
        errorMessage = nil
        isConfigured = true
        // Cancel any ongoing verification since we trust the setup process
        verificationTask?.cancel()
        verificationTask = nil
        
        // Don't warm up binaries here - let them warm up on first use
        // to avoid blocking the UI transition
    }
    
    /// Ensure binaries are ready for use (lazy initialization)
    /// Returns immediately if already ready, otherwise initializes
    func ensureBinariesReady() async {
        // First time check - load binaries if not done yet
        if !hasCheckedBinaries {
            hasCheckedBinaries = true
            await checkBinariesAsync()
        }
        
        // Warm up if configured but not warmed up yet
        if isConfigured && !hasWarmedUp {
            hasWarmedUp = true
            await warmUpBinaries()
        }
    }
    
    /// Check if binaries are ready without blocking
    var areBinariesReady: Bool {
        hasCheckedBinaries && isConfigured && hasWarmedUp
    }
    
    /// Warm up binaries to avoid first-run issues
    nonisolated private func warmUpBinaries() async {
        print("🔥 Warming up binaries...")
        
        // Get paths from MainActor
        let (ytDlpPath, ffmpegPath) = await MainActor.run {
            (self.ytDlpPath, self.ffmpegPath)
        }
        
        // Warm up yt-dlp with a simple operation
        if let ytDlpPath = ytDlpPath {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = ["--version"]
            process.environment = [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                print("✅ yt-dlp warmed up (exit code: \(process.terminationStatus))")
            } catch {
                print("⚠️ Failed to warm up yt-dlp: \(error)")
            }
        }
        
        // Warm up ffmpeg
        if let ffmpegPath = ffmpegPath {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = ["-version"]
            process.environment = [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                print("✅ ffmpeg warmed up (exit code: \(process.terminationStatus))")
            } catch {
                print("⚠️ Failed to warm up ffmpeg: \(error)")
            }
        }
    }
}

enum BinaryType: Sendable {
    case ytDlp
    case ffmpeg

    var displayName: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .ffmpeg: return "FFmpeg"
        }
    }
}