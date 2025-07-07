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
    private let processExecutor = ProcessExecutor()
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
        let (ytDlpPath, ffmpegPath) = await MainActor.run { 
            (binaryManager.ytDlpPath, binaryManager.ffmpegPath)
        }
        guard let ytDlpPath = ytDlpPath else {
            throw DownloadError.binaryNotFound("yt-dlp not configured")
        }
        guard let ffmpegPath = ffmpegPath else {
            throw DownloadError.binaryNotFound("FFmpeg not configured")
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

        // Build yt-dlp format expression from desired quality
        let formatString: String
        if job.quality.lowercased() == "best" {
            formatString = "bestvideo+bestaudio/best"
        } else if let h = Int(job.quality.lowercased().replacingOccurrences(of: "p", with: "")) {
            formatString = "bestvideo[height<=\(h)]+bestaudio[ext=m4a]/bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]/best"
        } else {
            formatString = "bestvideo[height<=720]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]/best"
        }
        
        print("🎬 yt-dlp format string: \(formatString)")
        print("🎬 Quality requested: \(job.quality)")
        print("🎬 URL: \(job.url)")
        
        // User agents for rotation
        let userAgents = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
        ]
        let randomUserAgent = userAgents.randomElement() ?? userAgents[0]
        
        let config = ProcessConfiguration(
            executablePath: ytDlpPath,
            arguments: [
                "--format", formatString,
                "--ffmpeg-location", ffmpegPath,  // Tell yt-dlp where FFmpeg is
                "--output", outputTemplate,
                "--no-playlist",
                "--newline",  // Output progress on new lines
                "--progress",  // Show progress
                // Safety parameters to avoid YouTube detection
                "--sleep-interval", "3",  // Sleep 3-8 seconds between playlist items
                "--max-sleep-interval", "8",
                "--user-agent", randomUserAgent,  // Randomize user agent
                "--referer", "https://www.youtube.com/",  // Add referer header
                "--quiet",  // Less verbose to reduce detection
                "--no-warnings",  // Suppress warnings
                job.url
            ],
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ],
            timeout: 900, // 15 minutes
            outputHandler: { [weak self] output in
                // Parse progress from yt-dlp output
                if let progress = parseProgress(from: output) {
                    Task { @MainActor in
                        self?.updateJobProgress(progress)
                    }
                }
            },
            combinedOutput: true  // Use single pipe for stdout and stderr like original
        )
        
        defer {
            // Schedule cleanup after a longer delay to prevent file deletion during use
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                self.cleanupTempDirectory(tempDir)
            }
        }
        
        do {
            let result = try await processExecutor.execute(config)
            
            if result.isSuccess {
                // Search for the file yt-dlp actually created (any extension)
                if let finalURL = try? FileManager.default
                    .contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    .first(where: { $0.lastPathComponent.hasPrefix(uniqueBaseName) }) {
                    
                    return finalURL.path
                } else {
                    // Rare, but critical if it happens
                    let errorOutput = result.errorString ?? result.outputString ?? "Unknown error, file not created."
                    print("❌ yt-dlp claimed success, but no file with prefix \(uniqueBaseName) was found in \(tempDir.path)")
                    throw DownloadError.downloadFailed(errorOutput)
                }
            } else {
                let errorOutput = result.errorString ?? result.outputString ?? "Unknown error"
                print("❌ yt-dlp failed with exit code: \(result.exitCode)")
                print("❌ yt-dlp error output: \(errorOutput)")
                throw DownloadError.downloadFailed(errorOutput)
            }
        } catch let error as ProcessExecutorError {
            switch error {
            case .timeout:
                throw DownloadError.downloadFailed("Download timed out after 15 minutes")
            case .launchFailed(let message):
                throw DownloadError.processError(message)
            case .executionFailed(_, let errorMessage):
                throw DownloadError.downloadFailed(errorMessage ?? "Unknown error")
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

// Global functions for parsing (nonisolated)
private nonisolated func parseYtDlpError(_ error: String) -> String {
    // Rate limiting detection - HIGHEST PRIORITY
    if error.contains("HTTP Error 429") || error.contains("Too Many Requests") {
        return "YouTube has temporarily blocked downloads from your IP. Please wait a few hours before trying again. Using a VPN may help."
    } else if error.contains("Sign in to confirm you're not a bot") {
        return "YouTube is requiring verification. This usually means too many downloads. Please wait before trying again."
    }
    
    // Consolidated fragment error handling
    else if error.contains("fragment") && error.contains("not found") {
        if error.contains("100%") {
            return "The video downloaded successfully but failed during processing. This can happen with longer videos or when YouTube's servers are busy. Please try again in a few moments."
        } else if error.contains("HTTP Error 403") {
            return "The download was interrupted during processing. This often happens when YouTube's servers timeout. Please try downloading again with a smaller quality setting or shorter clip duration."
        } else {
            return "The video stream was interrupted during processing. This typically happens when YouTube's CDN tokens expire. Please try downloading again with a lower quality setting."
        }
    }
    
    // Common yt-dlp error patterns and user-friendly messages
    else if error.contains("Sign in to confirm your age") || error.contains("age-restricted") {
        return "This video is age-restricted. YouTube requires sign-in which is not supported."
    } else if error.contains("Private video") {
        return "This video is private and cannot be downloaded."
    } else if error.contains("Video unavailable") {
        return "This video is unavailable or has been removed."
    } else if error.contains("members-only") {
        return "This video is for members only and cannot be downloaded."
    } else if error.contains("geo-restricted") || error.contains("not available in your country") {
        return "This video is not available in your region."
    } else if error.contains("copyright") {
        return "This video has been blocked due to copyright."
    } else if error.contains("HTTP Error 403") {
        return "Access denied. The video may be restricted or removed."
    } else if error.contains("HTTP Error 404") {
        return "Video not found. Please check the URL."
    } else if error.contains("No video formats found") {
        return "No downloadable video formats found. The video may be restricted."
    } else if error.contains("ERROR:") {
        // Extract just the error message after ERROR:
        if let errorStart = error.range(of: "ERROR:") {
            let errorMsg = String(error[errorStart.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Remove YouTube URL if present for cleaner message
            if let urlStart = errorMsg.range(of: "https://") {
                return String(errorMsg[..<urlStart.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return errorMsg
        }
    }
    
    // Return original error if no pattern matches
    return error
}

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
        case .binaryNotFound(let message):
            return "Setup required: \(message)"
        case .invalidURL:
            return "Invalid YouTube URL. Please check the link and try again."
        case .downloadFailed(let details):
            // Parse yt-dlp error for user-friendly message
            let userFriendlyError = parseYtDlpError(details)
            return userFriendlyError
        case .processError(let message):
            return "Process error: \(message)"
        case .fileNotFound:
            return "Downloaded file not found. Please try again."
        case .networkError(let message):
            return "Network error: \(message)"
        case .diskSpaceError(let message):
            return "Disk space error: \(message)"
        }
    }

    func toAppError() -> AppError {
        switch self {
        case .binaryNotFound(let message):
            return .binaryNotFound(message)
        case .invalidURL:
            return .invalidInput(self.errorDescription ?? "Invalid URL")
        case .downloadFailed(_), .processError(_), .fileNotFound:
            // Use the actual error description which now includes details
            return .downloadFailed(self.errorDescription ?? "Download failed")
        case .networkError(let message):
            return .network(message)
        case .diskSpaceError(let message):
            return .diskSpace(message)
        }
    }
}
