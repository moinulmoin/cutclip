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
    private let processExecutor = ProcessExecutor()

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
            await updateProgress(0.1, "Downloading required tools (1/2)...")
            try await downloadYtDlp()

            // Step 2: Download additional tools
            await updateProgress(0.5, "Downloading additional tools (2/2)...")
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
        // Use the universal macOS binary which is more compatible
        let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        let destinationURL = binDirectory.appendingPathComponent("yt-dlp")

        // Retry logic with exponential backoff for large binary downloads
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: ytDlpURL)
                
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                
                // Make executable immediately after download
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
                
                // Remove quarantine attribute from yt-dlp binary
                let removeQuarantine = Process()
                removeQuarantine.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                removeQuarantine.arguments = ["-d", "com.apple.quarantine", destinationURL.path]
                try? removeQuarantine.run()
                removeQuarantine.waitUntilExit()
                if attempt > 1 {
                    print("✅ yt-dlp download succeeded on attempt \(attempt)")
                }
                return
            } catch {
                lastError = error
                LoggingService.shared.error("yt-dlp download failed on attempt \(attempt)/3: \(error.localizedDescription)", category: "setup", error: error)

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        LoggingService.shared.error("yt-dlp download failed after 3 attempts", category: "setup")
        throw lastError ?? SetupError.downloadFailed("Failed to download yt-dlp")
    }

    nonisolated private func downloadFFmpeg() async throws {
        // Use static FFmpeg build from evermeet.cx - proven to work well with yt-dlp
        // This provides a build with all necessary codecs for YouTube video processing
        let ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")!
        
        let destinationURL = binDirectory.appendingPathComponent("ffmpeg.zip")

        // Retry logic with exponential backoff for large binary downloads
        var lastError: Error?
        for attempt in 1...3 {
            do {
                // Use default URLSession without timeout for slow networks
                let session = URLSession.shared
                
                let (tempURL, response) = try await session.download(from: ffmpegURL)
                
                // Check HTTP response
                if let httpResponse = response as? HTTPURLResponse {
                    print("📊 HTTP Status: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        throw SetupError.downloadFailed("HTTP error \(httpResponse.statusCode)")
                    }
                }
                
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
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
        let tempExtractDir = binDirectory.appendingPathComponent("ffmpeg_temp")
        
        // Create temp directory
        try? FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        
        let config = ProcessConfiguration(
            executablePath: "/usr/bin/unzip",
            arguments: ["-o", zipURL.path, "-d", tempExtractDir.path],
            timeout: 30 // 30 seconds should be enough for extraction
        )

        let success = try await processExecutor.executeSimple(config)
        if !success {
            throw SetupError.extractionFailed("Failed to extract FFmpeg")
        }

        // Move ffmpeg binary to expected location
        // evermeet.cx archives have the binary directly in the root
        let extractedFFmpeg = binDirectory.appendingPathComponent("ffmpeg")
        let rootFFmpeg = tempExtractDir.appendingPathComponent("ffmpeg")
        
        if FileManager.default.fileExists(atPath: rootFFmpeg.path) {
            // Remove existing if present
            try? FileManager.default.removeItem(at: extractedFFmpeg)
            try FileManager.default.moveItem(at: rootFFmpeg, to: extractedFFmpeg)
        } else {
            throw SetupError.extractionFailed("FFmpeg binary not found in archive")
        }
        
        // Remove quarantine attribute from FFmpeg binary
        LoggingService.shared.info("Removing quarantine from FFmpeg at: \(extractedFFmpeg.path)", category: "setup")
        
        // First check if quarantine exists
        let checkQuarantine = Process()
        checkQuarantine.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        checkQuarantine.arguments = ["-l", extractedFFmpeg.path]
        let checkPipe = Pipe()
        checkQuarantine.standardOutput = checkPipe
        
        do {
            try checkQuarantine.run()
            checkQuarantine.waitUntilExit()
            
            let data = try checkPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                LoggingService.shared.debug("FFmpeg attributes before removal: \(output.trimmingCharacters(in: .whitespacesAndNewlines))", category: "setup")
            }
        } catch {
            LoggingService.shared.error("Failed to check FFmpeg attributes: \(error)", category: "setup")
        }
        
        // Remove quarantine
        let removeQuarantine = Process()
        removeQuarantine.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        removeQuarantine.arguments = ["-d", "com.apple.quarantine", extractedFFmpeg.path]
        
        do {
            try removeQuarantine.run()
            removeQuarantine.waitUntilExit()
            
            if removeQuarantine.terminationStatus == 0 {
                LoggingService.shared.info("Successfully removed quarantine from FFmpeg", category: "setup")
            } else {
                LoggingService.shared.error("Failed to remove quarantine, exit code: \(removeQuarantine.terminationStatus)", category: "setup")
            }
        } catch {
            LoggingService.shared.error("Error removing quarantine: \(error)", category: "setup")
        }
        
        // Verify quarantine was removed
        let verifyQuarantine = Process()
        verifyQuarantine.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        verifyQuarantine.arguments = ["-l", extractedFFmpeg.path]
        let verifyPipe = Pipe()
        verifyQuarantine.standardOutput = verifyPipe
        
        do {
            try verifyQuarantine.run()
            verifyQuarantine.waitUntilExit()
            
            let data = try verifyPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                LoggingService.shared.debug("FFmpeg attributes after removal: \(output.isEmpty ? "(none)" : output.trimmingCharacters(in: .whitespacesAndNewlines))", category: "setup")
            }
        } catch {
            LoggingService.shared.error("Failed to verify FFmpeg attributes: \(error)", category: "setup")
        }

        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
        try? FileManager.default.removeItem(at: tempExtractDir)
    }

    nonisolated private func makeExecutable() throws {
        let ytDlpPath = binDirectory.appendingPathComponent("yt-dlp").path
        let ffmpegPath = binDirectory.appendingPathComponent("ffmpeg").path

        // Make files executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytDlpPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegPath)
        
        // Remove quarantine attributes first
        removeQuarantine(from: ytDlpPath)
        removeQuarantine(from: ffmpegPath)
        
        // Sign binaries with ad-hoc signature to prevent Gatekeeper issues
        // This is crucial for notarized apps to work properly
        signBinaryAdHoc(at: ytDlpPath)
        signBinaryAdHoc(at: ffmpegPath)
    }
    
    nonisolated private func removeQuarantine(from path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", path]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                LoggingService.shared.info("Removed quarantine from \(URL(fileURLWithPath: path).lastPathComponent)", category: "setup")
            }
        } catch {
            // It's OK if this fails - the attribute might not exist
            LoggingService.shared.debug("No quarantine to remove from \(URL(fileURLWithPath: path).lastPathComponent)", category: "setup")
        }
    }
    
    nonisolated private func signBinaryAdHoc(at path: String) {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        
        // First remove existing signature completely
        let removeSignature = Process()
        removeSignature.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        removeSignature.arguments = ["--remove-signature", path]
        
        do {
            try removeSignature.run()
            removeSignature.waitUntilExit()
            LoggingService.shared.debug("Removed existing signature from \(fileName)", category: "setup")
        } catch {
            LoggingService.shared.debug("No existing signature to remove from \(fileName)", category: "setup")
        }
        
        // For PyInstaller binaries like yt-dlp, use less restrictive signing
        let isYtDlp = fileName == "yt-dlp"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        
        if isYtDlp {
            // For yt-dlp, don't use hardened runtime as it interferes with PyInstaller's extraction
            process.arguments = [
                "--force",
                "--sign", "-",
                "--timestamp=none",
                path
            ]
        } else {
            // For regular binaries like ffmpeg, use hardened runtime
            process.arguments = [
                "--force",
                "--sign", "-",
                "--timestamp=none",
                "--options", "runtime",
                path
            ]
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                LoggingService.shared.info("Successfully signed \(fileName) with ad-hoc signature", category: "setup")
            } else {
                LoggingService.shared.error("Failed to sign \(fileName), exit code: \(process.terminationStatus)", category: "setup")
            }
        } catch {
            LoggingService.shared.error("Error signing \(fileName): \(error)", category: "setup")
        }
    }

    nonisolated private func verifyBinaries() async throws {
        let ytDlpPath = binDirectory.appendingPathComponent("yt-dlp").path
        let ffmpegPath = binDirectory.appendingPathComponent("ffmpeg").path
        
        LoggingService.shared.info("Verifying binaries - yt-dlp: \(ytDlpPath), ffmpeg: \(ffmpegPath)", category: "setup")

        // Test yt-dlp with retry logic
        var ytDlpWorking = false
        for attempt in 1...3 {
            ytDlpWorking = await testBinary(path: ytDlpPath, args: ["--help"])
            if ytDlpWorking {
                break
            }
            if attempt < 3 {
                LoggingService.shared.warning("yt-dlp verification attempt \(attempt) failed, retrying...", category: "setup")
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        guard ytDlpWorking else {
            LoggingService.shared.error("yt-dlp verification failed after 3 attempts. The downloaded tools may be corrupted.", category: "setup")
            throw SetupError.verificationFailed("yt-dlp verification failed after 3 attempts. The downloaded tools may be corrupted.")
        }

        // Test ffmpeg with retry logic
        var ffmpegWorking = false
        for attempt in 1...3 {
            ffmpegWorking = await testBinary(path: ffmpegPath, args: ["-version"])
            if ffmpegWorking {
                break
            }
            if attempt < 3 {
                print("⚠️ FFmpeg verification attempt \(attempt) failed, retrying...")
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        guard ffmpegWorking else {
            throw SetupError.verificationFailed("FFmpeg verification failed after 3 attempts")
        }
    }

    nonisolated private func testBinary(path: String, args: [String]) async -> Bool {
        // Check if file exists first
        guard FileManager.default.fileExists(atPath: path) else {
            LoggingService.shared.error("Binary not found at path: \(path)", category: "setup")
            return false
        }
        
        // Check if file is executable
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                LoggingService.shared.debug("Binary permissions for \(URL(fileURLWithPath: path).lastPathComponent): \(String(format: "%o", permissions.intValue))", category: "setup")
            }
        } catch {
            LoggingService.shared.error("Failed to get binary attributes: \(error)", category: "setup")
        }
        
        // Use full path execution - no need for PATH since we're using absolute paths
        let config = ProcessConfiguration(
            executablePath: path,
            arguments: args,
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ],
            timeout: 10 // 10 seconds for binary test
        )

        do {
            let result = try await processExecutor.execute(config)
            LoggingService.shared.debug("Binary test result for \(URL(fileURLWithPath: path).lastPathComponent) - Exit code: \(result.exitCode)", category: "setup")
            if let output = result.outputString, !output.isEmpty {
                LoggingService.shared.debug("Output: \(output.prefix(200))...", category: "setup")
            }
            if let error = result.errorString, !error.isEmpty {
                LoggingService.shared.debug("Error: \(error.prefix(200))...", category: "setup")
            }
            
            // Be more lenient with exit codes
            // Some binaries return non-zero for --help or --version
            if result.exitCode == 0 {
                return true
            }
            
            // Check if we got expected output even with non-zero exit code
            let output = (result.outputString ?? "") + (result.errorString ?? "")
            let lowercaseOutput = output.lowercased()
            
            // For yt-dlp --help, check if we got help text
            if args.contains("--help") && (lowercaseOutput.contains("usage:") || lowercaseOutput.contains("options:")) {
                LoggingService.shared.info("Binary produced help output despite exit code \(result.exitCode)", category: "setup")
                return true
            }
            
            // For ffmpeg -version, check if we got version info
            if args.contains("-version") && (lowercaseOutput.contains("ffmpeg") || lowercaseOutput.contains("version")) {
                print("✅ Binary produced version output despite exit code \(result.exitCode)")
                return true
            }
            
            return false
        } catch {
            print("❌ Binary test failed with error: \(error)")
            return false
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

extension ProcessInfo {
    var machineHardwareName: String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        // Remove null terminator and convert to String
        let machineString = machine.withUnsafeBufferPointer { buffer in
            let data = Data(buffer: buffer)
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
        return machineString
    }
}