//
//  AutoSetupService.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

@MainActor
class AutoSetupService: ObservableObject, Sendable {
    @Published var setupProgress: Double = 0.0
    @Published var setupMessage: String = "Preparing..."
    @Published var isSetupComplete: Bool = false
    @Published var setupError: String?

    private let binDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        binDirectory = appSupport.appendingPathComponent("CutClip/bin")

        // Create bin directory if it doesn't exist
        try? FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    }

    nonisolated func performAutoSetup() async {
        await MainActor.run {
            self.setupProgress = 0.0
            self.setupError = nil
            self.isSetupComplete = false
        }

        do {
            // Step 1: Download tools
            await updateProgress(0.1, "Downloading required components...")
            try await downloadYtDlp()

            // Step 2: Download additional tools
            await updateProgress(0.5, "Installing additional components...")
            try await downloadFFmpeg()

            // Step 3: Make executable
            await updateProgress(0.8, "Configuring tools...")
            try makeExecutable()

            // Step 4: Verify
            await updateProgress(0.9, "Finalizing setup...")
            try await verifyBinaries()

            // Complete
            await updateProgress(1.0, "Setup complete! 🎉")
            await MainActor.run {
                self.isSetupComplete = true
            }

        } catch {
            await MainActor.run {
                // Provide specific error messages based on failure type
                if let setupError = error as? SetupError {
                    switch setupError {
                    case .downloadFailed(let message):
                        if message.contains("network") || message.contains("connection") {
                            self.setupError = "No internet connection. Please check your connection and try again."
                        } else if message.contains("space") || message.contains("disk") {
                            self.setupError = "Insufficient disk space. Please free up space and try again."
                        } else {
                            self.setupError = "Download failed. Please check your internet connection and try again."
                        }
                    case .extractionFailed(_):
                        self.setupError = "Failed to extract downloaded files. Please try again or check disk space."
                    case .verificationFailed(let message):
                        self.setupError = "Setup verification failed: \(message). The downloaded tools may be corrupted."
                    case .permissionError(_):
                        self.setupError = "Permission denied. Please run the app with appropriate permissions."
                    }
                } else if error is URLError {
                    self.setupError = "No internet connection. Please check your connection and try again."
                } else if error.localizedDescription.contains("space") || error.localizedDescription.contains("disk") {
                    self.setupError = "Insufficient disk space. Please free up space and try again."
                } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                    self.setupError = "Network error. Please check your connection and try again."
                } else {
                    self.setupError = "Setup failed: \(error.localizedDescription). Please try again."
                }

                print("❌ Setup failed with error: \(error)")
            }
        }
    }

    nonisolated private func downloadYtDlp() async throws {
        let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        let destinationURL = binDirectory.appendingPathComponent("yt-dlp")

        // Retry logic with exponential backoff for large binary downloads
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: ytDlpURL)
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                if attempt > 1 {
                    print("✅ yt-dlp download succeeded on attempt \(attempt)")
                }
                return
            } catch {
                lastError = error
                print("⚠️ yt-dlp download failed on attempt \(attempt)/3: \(error.localizedDescription)")

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        print("❌ yt-dlp download failed after 3 attempts")
        throw lastError ?? SetupError.downloadFailed("Failed to download yt-dlp")
    }

    nonisolated private func downloadFFmpeg() async throws {
        // For macOS, we'll use a static build from a reliable source
        // This is a simplified approach - in production you might want to use official builds
        let ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")!
        let destinationURL = binDirectory.appendingPathComponent("ffmpeg.zip")

        // Retry logic with exponential backoff for large binary downloads
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: ffmpegURL)
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                if attempt > 1 {
                    print("✅ FFmpeg download succeeded on attempt \(attempt)")
                }
                break
            } catch {
                lastError = error
                print("⚠️ FFmpeg download failed on attempt \(attempt)/3: \(error.localizedDescription)")

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        if lastError != nil {
            print("❌ FFmpeg download failed after 3 attempts")
            throw lastError ?? SetupError.downloadFailed("Failed to download FFmpeg")
        }

        // Extract the zip
        try await extractFFmpeg()
    }

    nonisolated private func extractFFmpeg() async throws {
        let zipURL = binDirectory.appendingPathComponent("ffmpeg.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", binDirectory.path]
        
        // Secure process environment
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": NSTemporaryDirectory()
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw SetupError.extractionFailed("Failed to extract FFmpeg")
        }

        // Move ffmpeg binary to expected location
        let extractedFFmpeg = binDirectory.appendingPathComponent("ffmpeg")
        if !FileManager.default.fileExists(atPath: extractedFFmpeg.path) {
            // Look for ffmpeg binary in extracted contents
            let contents = try FileManager.default.contentsOfDirectory(at: binDirectory, includingPropertiesForKeys: nil)
            if let ffmpegBinary = contents.first(where: { $0.lastPathComponent == "ffmpeg" || $0.pathExtension == "" }) {
                try FileManager.default.moveItem(at: ffmpegBinary, to: extractedFFmpeg)
            }
        }

        // Clean up zip file
        try? FileManager.default.removeItem(at: zipURL)
    }

    nonisolated private func makeExecutable() throws {
        let ytDlpPath = binDirectory.appendingPathComponent("yt-dlp").path
        let ffmpegPath = binDirectory.appendingPathComponent("ffmpeg").path

        // Make files executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytDlpPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegPath)
    }

    nonisolated private func verifyBinaries() async throws {
        let ytDlpPath = binDirectory.appendingPathComponent("yt-dlp").path
        let ffmpegPath = binDirectory.appendingPathComponent("ffmpeg").path

        // Test yt-dlp
        let ytDlpWorking = await testBinary(path: ytDlpPath, args: ["--version"])
        guard ytDlpWorking else {
            throw SetupError.verificationFailed("yt-dlp verification failed")
        }

        // Test ffmpeg
        let ffmpegWorking = await testBinary(path: ffmpegPath, args: ["-version"])
        guard ffmpegWorking else {
            throw SetupError.verificationFailed("FFmpeg verification failed")
        }
    }

    nonisolated private func testBinary(path: String, args: [String]) async -> Bool {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            
            // Secure process environment
            process.environment = [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ]

            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    nonisolated private func updateProgress(_ progress: Double, _ message: String) async {
        await MainActor.run {
            self.setupProgress = progress
            self.setupMessage = message
        }

        // Small delay for visual feedback
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }

    // Public method to get binary paths after setup
    nonisolated func getBinaryPaths() -> (ytDlp: String?, ffmpeg: String?) {
        let ytDlpPath = binDirectory.appendingPathComponent("yt-dlp").path
        let ffmpegPath = binDirectory.appendingPathComponent("ffmpeg").path

        let ytDlpExists = FileManager.default.fileExists(atPath: ytDlpPath)
        let ffmpegExists = FileManager.default.fileExists(atPath: ffmpegPath)

        return (
            ytDlp: ytDlpExists ? ytDlpPath : nil,
            ffmpeg: ffmpegExists ? ffmpegPath : nil
        )
    }
}

enum SetupError: LocalizedError, Sendable {
    case downloadFailed(String)
    case extractionFailed(String)
    case verificationFailed(String)
    case permissionError(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        case .verificationFailed(let message):
            return "Verification failed: \(message)"
        case .permissionError(let message):
            return "Permission error: \(message)"
        }
    }
}