//
//  DownloadService.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

@MainActor
class DownloadService: ObservableObject, Sendable {
    private let binaryManager: BinaryManager
    @Published var currentJob: ClipJob?

    nonisolated init(binaryManager: BinaryManager) {
        self.binaryManager = binaryManager
    }

    nonisolated func isValidYouTubeURL(_ urlString: String) -> Bool {
        // Basic input sanitization
        guard !urlString.isEmpty,
              urlString.count <= 2048, // Reasonable URL length limit
              !urlString.contains("\0"),
              !urlString.contains("\n"),
              !urlString.contains("\r") else {
            return false
        }

        guard let url = URL(string: urlString) else { return false }
        guard let host = url.host else { return false }

        // Check for valid YouTube hosts
        let validHosts = ["youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com"]
        guard validHosts.contains(host.lowercased()) else { return false }

        // Additional security checks
        guard url.scheme == "https" || url.scheme == "http" else { return false }

        // Check for suspicious patterns
        let suspiciousPatterns = ["javascript:", "data:", "file:", "ftp:"]
        let lowercaseURL = urlString.lowercased()
        for pattern in suspiciousPatterns {
            if lowercaseURL.contains(pattern) {
                return false
            }
        }

        return true
    }

    nonisolated func downloadVideo(for job: ClipJob) async throws -> String {
        let ytDlpPath = await MainActor.run { binaryManager.ytDlpPath }
        guard let ytDlpPath = ytDlpPath else {
            throw DownloadError.binaryNotFound("yt-dlp not configured")
        }

        guard isValidYouTubeURL(job.url) else {
            throw DownloadError.invalidURL
        }

        // Create temporary directory for downloads
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CutClip")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Generate a unique, deterministic base name (no extension yet)
        let uniqueBaseName = UUID().uuidString
        // Allow yt-dlp to choose the right container by expanding %(ext)s
        let outputTemplate = tempDir.appendingPathComponent("\(uniqueBaseName).%(ext)s").path

        // Use an actor to manage state instead of captured variables
        let stateManager = ProcessStateManager()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)

            // Build yt-dlp format expression from desired quality
            // Remove mp4 restriction to allow webm and other formats
            let formatString: String
            if job.quality.lowercased() == "best" {
                formatString = "bestvideo+bestaudio/best"
            } else if let h = Int(job.quality.lowercased().replacingOccurrences(of: "p", with: "")) {
                // Always use height as the quality constraint for consistency
                // The ClipService will handle aspect ratio scaling appropriately
                formatString = "bestvideo[height<=\(h)]+bestaudio[ext=m4a]/bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]/best"
            } else {
                formatString = "bestvideo[height<=720]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]/best"
            }

            process.arguments = [
                "--format", formatString,
                "--output", outputTemplate,
                "--no-playlist",
                "--newline",  // Output progress on new lines
                "--progress",  // Show progress
                job.url
            ]
            
            print("🎬 yt-dlp format string: \(formatString)")
            print("🎬 Quality requested: \(job.quality)")

            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe
            
            // Security: Set restrictive environment
            process.environment = [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ]

            // Use thread-safe actor for download tracking
            let errorBuffer = ErrorBuffer()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    Task {
                        await errorBuffer.appendData(data)
                        let output = String(data: data, encoding: .utf8) ?? ""

                        // Parse progress from yt-dlp output
                        if let progress = parseProgress(from: output) {
                            await MainActor.run {
                                self.updateJobProgress(progress)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { process in
                Task {
                    defer {
                        // Schedule cleanup after a longer delay to prevent file deletion during use
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                            self.cleanupTempDirectory(tempDir)
                        }
                    }

                    let didResume = await stateManager.markResumedAndCleanup {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        if process.isRunning {
                            process.terminate()
                        }
                    }

                    if !didResume {
                        if process.terminationStatus == 0 {
                            // Search for the file yt-dlp actually created (any extension)
                            if let finalURL = try? FileManager.default
                                .contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                                .first(where: { $0.lastPathComponent.hasPrefix(uniqueBaseName) }) {

                                continuation.resume(returning: finalURL.path)
                            } else {
                                // Rare, but critical if it happens
                                let outputData = await errorBuffer.outputData
                                let errorOutput = String(data: outputData, encoding: .utf8) ?? "Unknown error, file not created."
                                print("❌ yt-dlp claimed success, but no file with prefix \(uniqueBaseName) was found in \(tempDir.path)")
                                continuation.resume(throwing: DownloadError.downloadFailed(errorOutput))
                            }
                        } else {
                            let outputData = await errorBuffer.outputData
                            let errorOutput = String(data: outputData, encoding: .utf8) ?? "Unknown error"
                            continuation.resume(throwing: DownloadError.downloadFailed(errorOutput))
                        }
                    }
                }
            }

            // Add timeout to prevent hanging downloads (15 minutes max)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000_000) // 15 minutes
                let didResume = await stateManager.markResumedAndCleanup {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning {
                        process.terminate()
                    }
                }
                if !didResume {
                    continuation.resume(throwing: DownloadError.downloadFailed("Download timed out after 15 minutes"))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: DownloadError.processError(error.localizedDescription))
            }
        }
    }

    nonisolated private func updateJobProgress(_ progress: Double) {
        Task { @MainActor in
            guard let job = currentJob else { return }
            let updatedJob = ClipJob(
                url: job.url,
                startTime: job.startTime,
                endTime: job.endTime,
                aspectRatio: job.aspectRatio,
                status: job.status,
                progress: progress / 100.0,
                downloadedFilePath: job.downloadedFilePath,
                outputFilePath: job.outputFilePath,
                errorMessage: job.errorMessage
            )
            currentJob = updatedJob
        }
    }

    // MARK: - Cleanup

    private nonisolated func cleanupTempDirectory(_ tempDir: URL) {
        Task {
            do {
                // Only remove files older than 2 hours to avoid interfering with active downloads
                let cutoffDate = Date().addingTimeInterval(-7200) // 2 hours instead of 1
                let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])

                for file in files {
                    if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < cutoffDate {

                        // Check if file is still being accessed before deletion
                        if !isFileInUse(file) {
                            try? FileManager.default.removeItem(at: file)
                            print("🗑️ Cleaned up old temp file: \(file.lastPathComponent)")
                        } else {
                            print("⚠️ Skipping cleanup of file in use: \(file.lastPathComponent)")
                        }
                    }
                }
            } catch {
                print("Warning: Failed to clean up temp directory: \(error)")
            }
        }
    }

    /// Check if file is currently being accessed by another process
    private nonisolated func isFileInUse(_ fileURL: URL) -> Bool {
        do {
            // Try to open file for writing - if it fails, file may be in use
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.closeFile()
            return false
        } catch {
            // If we can't open for writing, assume it's in use
            return true
        }
    }
}

// Thread-safe actor for buffering error output
private actor ErrorBuffer {
    private(set) var outputData = Data()

    func appendData(_ data: Data) {
        outputData.append(data)
    }
}

// Thread-safe actor for process state management
private actor ProcessStateManager {
    private var hasResumed = false

    func markResumedAndCleanup(_ cleanup: () -> Void) -> Bool {
        if hasResumed {
            return true
        }
        hasResumed = true
        cleanup()
        return false
    }
}

// Global functions for parsing (nonisolated)
private nonisolated func parseProgress(from output: String) -> Double? {
    // Look for progress patterns like "[download] 25.5% of 15.30MiB"
    let progressPattern = #"\[download\]\s+(\d+\.?\d*)%"#
    let regex = try? NSRegularExpression(pattern: progressPattern)
    let range = NSRange(output.startIndex..<output.endIndex, in: output)

    if let match = regex?.firstMatch(in: output, range: range) {
        let matchRange = Range(match.range(at: 1), in: output)!
        let percentString = String(output[matchRange])
        return Double(percentString)
    }

    return nil
}

enum DownloadError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case invalidURL
    case downloadFailed(String)
    case processError(String)
    case fileNotFound
    case networkError(String)
    case diskSpaceError(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(_):
            return "Setup required. Please configure required tools in Settings."
        case .invalidURL:
            return "Invalid YouTube URL. Please check the link and try again."
        case .downloadFailed(_):
            return "Video download failed. This video may be restricted."
        case .processError(_):
            return "Video download failed. This video may be restricted."
        case .fileNotFound:
            return "Video download failed. This video may be restricted."
        case .networkError(_):
            return "No internet connection. CutClip requires internet."
        case .diskSpaceError(_):
            return "Unable to download video. Please check your disk space."
        }
    }

    func toAppError() -> AppError {
        switch self {
        case .binaryNotFound(_):
            return .binaryNotFound("Setup required. Please configure required tools in Settings.")
        case .invalidURL:
            return .invalidInput("Invalid YouTube URL. Please check the link and try again.")
        case .downloadFailed(_):
            return .downloadFailed("Video download failed. This video may be restricted.")
        case .processError(_):
            return .downloadFailed("Video download failed. This video may be restricted.")
        case .fileNotFound:
            return .downloadFailed("Video download failed. This video may be restricted.")
        case .networkError(_):
            return .network("No internet connection. CutClip requires internet.")
        case .diskSpaceError(_):
            return .diskSpace("Unable to download video. Please check your disk space.")
        }
    }
}
