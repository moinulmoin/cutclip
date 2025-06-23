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
                pipe.fileHandleForReading.readabilityHandler = nil

                Task {
                    defer {
                        // DON'T clean up immediately - let the file be used by ClipService first
                        // self.cleanupTempDirectory(tempDir)
                        print("DEBUG: Skipping cleanup to allow ClipService to access file")
                    }
                    
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
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            print("DEBUG: Found \(files.count) files in temp directory")
            
            // Debug: Print all files
            for file in files {
                let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = resourceValues?.fileSize ?? 0
                print("DEBUG: File: \(file.lastPathComponent) (size: \(fileSize) bytes)")
            }
            
            // Filter for video files (not directories, and with reasonable size > 0)
            let videoFiles = files.filter { file in
                guard !file.hasDirectoryPath else { return false }
                
                // Check file size to ensure it's not empty
                let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = resourceValues?.fileSize ?? 0
                
                // Check for common video extensions
                let videoExtensions = ["mp4", "webm", "mkv", "avi", "mov", "flv", "m4v", "3gp"]
                let fileExtension = file.pathExtension.lowercased()
                
                return fileSize > 0 && videoExtensions.contains(fileExtension)
            }
            
            print("DEBUG: Found \(videoFiles.count) video files")
            
            if let videoFile = videoFiles.first {
                print("DEBUG: Using video file: \(videoFile.path)")
                continuation.resume(returning: videoFile.path)
            } else {
                // Debug: List all files found
                let allFiles = files.map { "\($0.lastPathComponent) (\($0.pathExtension))" }.joined(separator: ", ")
                let errorMessage = "No video files found in temp directory. Files present: \(allFiles.isEmpty ? "none" : allFiles)"
                print("DEBUG: \(errorMessage)")
                continuation.resume(throwing: DownloadError.fileNotFound)
            }
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
    // Look for multiple possible patterns from yt-dlp output
    let patterns = [
        #"\[download\] Destination: (.+)"#,           // Standard destination
        #"\[download\] (.+) has already been downloaded"#, // Already downloaded case
        #"has already been downloaded and merged into (.+)"#, // Merged case
        #"\[merger\] Merging formats into \"(.+)\""#,  // Format merging
        #"\[download\] 100% of .+ in .+ to (.+)"#     // Completion message with path
    ]
    
    for pattern in patterns {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        
        if let match = regex?.firstMatch(in: output, range: range) {
            let matchRange = Range(match.range(at: 1), in: output)!
            let filePath = String(output[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove quotes if present
            let cleanPath = filePath.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return cleanPath
        }
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
            return "Binary not found: \(message)"
        case .invalidURL:
            return "Invalid YouTube URL"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .processError(let message):
            return "Process error: \(message)"
        case .fileNotFound:
            return "Downloaded file not found"
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
            return .invalidInput("Invalid YouTube URL format")
        case .downloadFailed(let message):
            return .downloadFailed(message)
        case .processError(let message):
            return .downloadFailed(message)
        case .fileNotFound:
            return .fileSystem("Downloaded file not found")
        case .networkError(let message):
            return .network(message)
        case .diskSpaceError(let message):
            return .diskSpace(message)
        }
    }
}