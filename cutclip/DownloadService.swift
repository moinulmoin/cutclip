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

                        // Parse progress from yt-dlp output
                        if let progress = parseProgress(from: output) {
                            await MainActor.run {
                                self.updateJobProgress(progress)
                            }
                        }

                        // Look for downloaded file path
                        if let filePath = parseDownloadedFilePath(from: output) {
                            await downloadTracker.setDownloadedFilePath(filePath)
                        }
                    }
                }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil

                Task {
                    defer {
                        // Clean up temporary files on completion or failure
                        self.cleanupTempDirectory(tempDir)
                    }
                    
                    if process.terminationStatus == 0 {
                        if let filePath = await downloadTracker.downloadedFilePath {
                            continuation.resume(returning: filePath)
                        } else {
                            // Try to find the downloaded file in temp directory
                            do {
                                let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                                if let videoFile = files.first(where: { !$0.hasDirectoryPath }) {
                                    continuation.resume(returning: videoFile.path)
                                } else {
                                    continuation.resume(throwing: DownloadError.fileNotFound)
                                }
                            } catch {
                                continuation.resume(throwing: DownloadError.downloadFailed(error.localizedDescription))
                            }
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
    // Look for patterns like "[download] Destination: /path/to/file.mp4"
    let destinationPattern = #"\[download\] Destination: (.+)"#
    let regex = try? NSRegularExpression(pattern: destinationPattern)
    let range = NSRange(output.startIndex..<output.endIndex, in: output)

    if let match = regex?.firstMatch(in: output, range: range) {
        let matchRange = Range(match.range(at: 1), in: output)!
        return String(output[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
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