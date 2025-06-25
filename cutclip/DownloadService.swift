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

        // Let yt-dlp use the video title but sanitize it for filesystem safety
        let outputTemplate = tempDir.appendingPathComponent("%(title)s.%(ext)s").path

        // Use an actor to manage state instead of captured variables
        let stateManager = ProcessStateManager()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = [
                "--format", "best[height<=720]", // Limit to 720p for faster downloads
                "--output", outputTemplate,
                "--no-playlist",
                job.url
            ]

            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe

            // Use thread-safe actor for download tracking
            let downloadTracker = DownloadTracker()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    Task {
                        await downloadTracker.appendData(data)
                        let output = String(data: data, encoding: .utf8) ?? ""

                        // Debug: Print yt-dlp output to help diagnose file path issues
                        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            print("yt-dlp output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }

                        // Parse progress from yt-dlp output
                        if let progress = parseProgress(from: output) {
                            await MainActor.run {
                                self.updateJobProgress(progress)
                            }
                        }

                        // Look for downloaded file path
                        if let filePath = parseDownloadedFilePath(from: output) {
                            print("Parsed file path: \(filePath)")
                            await downloadTracker.setDownloadedFilePath(filePath)
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
                            if let filePath = await downloadTracker.downloadedFilePath {
                                print("DEBUG: Parsed file path: \(filePath)")
                                // Verify the parsed file actually exists
                                if FileManager.default.fileExists(atPath: filePath) {
                                    print("DEBUG: File exists at parsed path")
                                    continuation.resume(returning: filePath)
                                } else {
                                    print("DEBUG: File does NOT exist at parsed path, searching directory")
                                    // File doesn't exist at parsed path, fall back to directory search
                                    self.findDownloadedFile(in: tempDir, continuation: continuation)
                                }
                            } else {
                                print("DEBUG: No parsed path, searching directory")
                                // No parsed path, search directory
                                self.findDownloadedFile(in: tempDir, continuation: continuation)
                            }
                        } else {
                            let outputData = await downloadTracker.outputData
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

    // MARK: - Helper Methods

    private nonisolated func findDownloadedFile(in tempDir: URL, continuation: CheckedContinuation<String, Error>) {
        do {
            print("DEBUG: Searching temp directory: \(tempDir.path)")
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey])
            print("DEBUG: Found \(files.count) files in temp directory")

            // Debug: Print all files
            for file in files {
                let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let fileSize = resourceValues?.fileSize ?? 0
                let creationDate = resourceValues?.creationDate?.timeIntervalSinceNow ?? 0
                print("DEBUG: File: \(file.lastPathComponent) (size: \(fileSize) bytes, age: \(Int(-creationDate))s)")
            }

            // Filter for video files with additional criteria
            let videoFiles = files.compactMap { file -> (URL, Int, Date)? in
                guard !file.hasDirectoryPath else { return nil }

                // Check file size and creation date
                guard let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]),
                      let fileSize = resourceValues.fileSize,
                      let creationDate = resourceValues.creationDate else {
                    return nil
                }

                // Minimum file size check (100KB for video files)
                guard fileSize > 100_000 else { return nil }

                // Check for video file extensions (including common formats)
                let videoExtensions = ["mp4", "webm", "mkv", "avi", "mov", "flv", "m4v", "3gp", "ogg", "ogv"]
                let fileExtension = file.pathExtension.lowercased()

                guard videoExtensions.contains(fileExtension) else { return nil }

                return (file, fileSize, creationDate)
            }

            print("DEBUG: Found \(videoFiles.count) valid video files")

            if videoFiles.isEmpty {
                // Debug: List all files found
                let allFiles = files.map { "\($0.lastPathComponent) (\($0.pathExtension))" }.joined(separator: ", ")
                let errorMessage = "No video files found in temp directory. Files present: \(allFiles.isEmpty ? "none" : allFiles)"
                print("DEBUG: \(errorMessage)")
                continuation.resume(throwing: DownloadError.fileNotFound)
                return
            }

            // Sort by creation date (newest first) and then by file size (largest first)
            let sortedVideoFiles = videoFiles.sorted { file1, file2 in
                // First priority: newest file
                if file1.2.timeIntervalSince(file2.2) > 10 { // 10 second tolerance
                    return true
                } else if file2.2.timeIntervalSince(file1.2) > 10 {
                    return false
                } else {
                    // If files are similar in age, prefer larger file
                    return file1.1 > file2.1
                }
            }

            let selectedFile = sortedVideoFiles.first!.0
            print("DEBUG: Selected video file: \(selectedFile.path) (size: \(sortedVideoFiles.first!.1) bytes)")
            continuation.resume(returning: selectedFile.path)

        } catch {
            print("DEBUG: Error searching temp directory: \(error)")
            continuation.resume(throwing: DownloadError.downloadFailed("Failed to search temp directory: \(error.localizedDescription)"))
        }
    }

    // MARK: - Cleanup

    private nonisolated func cleanupTempDirectory(_ tempDir: URL) {
        Task {
            do {
                // Only remove files older than 1 hour to avoid interfering with active downloads
                let cutoffDate = Date().addingTimeInterval(-3600)
                let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])

                for file in files {
                    if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < cutoffDate {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            } catch {
                print("Warning: Failed to clean up temp directory: \(error)")
            }
        }
    }
}

// Thread-safe actor for download tracking
private actor DownloadTracker {
    private(set) var outputData = Data()
    private(set) var downloadedFilePath: String?

    func appendData(_ data: Data) {
        outputData.append(data)
    }

    func setDownloadedFilePath(_ filePath: String) {
        downloadedFilePath = filePath
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

private nonisolated func parseDownloadedFilePath(from output: String) -> String? {
    // Look for multiple possible patterns from yt-dlp output (in priority order)
    let patterns = [
        // Standard download completion with path
        #"\[download\] 100(?:\.0)?% of .+? in .+? to (.+?)(?:\n|$)"#,
        #"\[download\] 100(?:\.0)?% of .+? to (.+?)(?:\n|$)"#,

        // Standard destination announcement
        #"\[download\] Destination: (.+?)(?:\n|$)"#,

        // Already downloaded cases
        #"\[download\] (.+?) has already been downloaded"#,
        #"has already been downloaded and merged into \"?(.+?)\"?"#,

        // Format merging patterns
        #"\[merger\] Merging formats into \"(.+?)\""#,
        #"\[ffmpeg\] Merging formats into \"(.+?)\""#,

        // File operations
        #"Deleting original file (.+?) \(pass -k to keep\)"#,

        // Generic file path patterns (last resort)
        #"\"([^\"]+\.(?:mp4|webm|mkv|avi|mov|flv|m4v))\""#,
        #"([^\s]+\.(?:mp4|webm|mkv|avi|mov|flv|m4v))(?:\s|$)"#
    ]

    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)

            if let match = regex.firstMatch(in: output, range: range) {
                let matchRange = Range(match.range(at: 1), in: output)!
                let filePath = String(output[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Clean and validate the path
                let cleanPath = cleanFilePath(filePath)

                // Convert to absolute path if relative
                let absolutePath = makeAbsolutePath(cleanPath)

                // Final validation
                if isValidFilePath(absolutePath) {
                    print("📁 Parsed file path: \(absolutePath)")
                    return absolutePath
                }
            }
        }
    }

    return nil
}

private nonisolated func cleanFilePath(_ path: String) -> String {
    // Remove quotes (single, double, and smart quotes)
    var cleaned = path

    // Remove all types of quotes
    let quotesToRemove = ["\"", "'", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
    for quote in quotesToRemove {
        cleaned = cleaned.replacingOccurrences(of: quote, with: "")
    }

    // Remove any trailing line endings or control characters
    cleaned = cleaned.replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\t", with: "")

    return cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
}

private nonisolated func makeAbsolutePath(_ path: String) -> String {
    // If already absolute, return as-is
    if path.hasPrefix("/") {
        return path
    }

    // If relative, make it absolute based on current working directory
    let currentDir = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: currentDir).appendingPathComponent(path).path
}

private nonisolated func isValidFilePath(_ path: String) -> Bool {
    // Basic validation
    guard !path.isEmpty else { return false }

    // Must be absolute path for security
    guard path.hasPrefix("/") else { return false }

    // Check for dangerous patterns (but allow legitimate file paths)
    let dangerousPatterns = ["\0", ";", "|", "&", "`"]
    for pattern in dangerousPatterns {
        if path.contains(pattern) {
            return false
        }
    }

    return true
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
