//
//  VideoInfoService.swift
//  cutclip
//
//  Created by Moinul Moin on 6/27/25.
//

import Foundation

@MainActor
class VideoInfoService: ObservableObject, Sendable {
    private let binaryManager: BinaryManager
    @Published var isLoading: Bool = false
    @Published var currentVideoInfo: VideoInfo?

    nonisolated init(binaryManager: BinaryManager) {
        self.binaryManager = binaryManager
    }

    nonisolated func isValidYouTubeURL(_ urlString: String) -> Bool {
        // Reuse validation logic from DownloadService
        guard !urlString.isEmpty,
              urlString.count <= 2048,
              !urlString.contains("\0"),
              !urlString.contains("\n"),
              !urlString.contains("\r") else {
            return false
        }

        guard let url = URL(string: urlString) else { return false }
        guard let host = url.host else { return false }

        let validHosts = ["youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com"]
        guard validHosts.contains(host.lowercased()) else { return false }

        guard url.scheme == "https" || url.scheme == "http" else { return false }

        let suspiciousPatterns = ["javascript:", "data:", "file:", "ftp:"]
        let lowercaseURL = urlString.lowercased()
        for pattern in suspiciousPatterns {
            if lowercaseURL.contains(pattern) {
                return false
            }
        }

        return true
    }

    func loadVideoInfo(for urlString: String) async throws -> VideoInfo {
        let ytDlpPath = await MainActor.run { binaryManager.ytDlpPath }
        guard let ytDlpPath = ytDlpPath else {
            throw VideoInfoError.binaryNotFound("yt-dlp not configured")
        }

        guard isValidYouTubeURL(urlString) else {
            throw VideoInfoError.invalidURL
        }

        await MainActor.run {
            self.isLoading = true
        }

        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }

        let stateManager = ProcessStateManager()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = [
                "--dump-json",
                "--no-playlist",
                "--no-warnings",
                urlString
            ]

            // Secure process environment - same as DownloadService
            process.environment = [
                "PATH": "/usr/bin:/bin",
                "HOME": NSTemporaryDirectory()
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let outputBuffer = OutputBuffer()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    Task {
                        await outputBuffer.appendData(data)
                    }
                }
            }

            process.terminationHandler = { process in
                Task {
                    // --- flush anything still waiting in the pipe -----------------
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if let tailData = try? pipe.fileHandleForReading.readToEnd() {
                        await outputBuffer.appendData(tailData)
                    }
                    // ----------------------------------------------------------------

                    let didResume = await stateManager.markResumedAndCleanup {
                        if process.isRunning {
                            process.terminate()
                        }
                    }

                    if !didResume {
                        if process.terminationStatus == 0 {
                            // Success - parse the (now complete) JSON output
                            let outputData = await outputBuffer.outputData
                            do {
                                let videoInfo = try await self.parseVideoInfo(from: outputData)
                                await MainActor.run {
                                    self.currentVideoInfo = videoInfo
                                }
                                continuation.resume(returning: videoInfo)
                            } catch {
                                continuation.resume(throwing: VideoInfoError.parsingFailed(error.localizedDescription))
                            }
                        } else {
                            // Error - process failed
                            let outputData = await outputBuffer.outputData
                            let errorOutput = String(data: outputData, encoding: .utf8) ?? "Unknown error"
                            // Parse common yt-dlp errors
                            let error = self.parseYtDlpError(from: errorOutput)
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }

            // Add timeout to prevent hanging (30 seconds should be enough for metadata)
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                let didResume = await stateManager.markResumedAndCleanup {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning {
                        process.terminate()
                    }
                }
                if !didResume {
                    continuation.resume(throwing: VideoInfoError.timeout)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: VideoInfoError.processError(error.localizedDescription))
            }
        }
    }

    private nonisolated func parseVideoInfo(from data: Data) async throws -> VideoInfo {
        let decoder = JSONDecoder()

        do {
            let ytDlpInfo = try decoder.decode(YtDlpVideoInfo.self, from: data)
            return ytDlpInfo.toVideoInfo()
        } catch {
            // If direct decoding fails, try to extract JSON from output
            if let jsonString = String(data: data, encoding: .utf8) {
                // Sometimes yt-dlp outputs multiple lines, we want the last JSON line
                let lines = jsonString.components(separatedBy: .newlines)
                for line in lines.reversed() {
                    if line.hasPrefix("{") && line.hasSuffix("}") {
                        if let lineData = line.data(using: .utf8) {
                            do {
                                let ytDlpInfo = try decoder.decode(YtDlpVideoInfo.self, from: lineData)
                                return ytDlpInfo.toVideoInfo()
                            } catch {
                                continue
                            }
                        }
                    }
                }
            }

            throw VideoInfoError.parsingFailed("Failed to parse video information: \(error.localizedDescription)")
        }
    }

    private nonisolated func parseYtDlpError(from output: String) -> VideoInfoError {
        let lowercaseOutput = output.lowercased()

        if lowercaseOutput.contains("private video") || lowercaseOutput.contains("video unavailable") {
            return .videoUnavailable("This video is private or unavailable")
        } else if lowercaseOutput.contains("video not found") || lowercaseOutput.contains("http error 404") {
            return .videoNotFound("Video not found")
        } else if lowercaseOutput.contains("sign in to confirm your age") || lowercaseOutput.contains("age-restricted") {
            return .ageRestricted("This video is age-restricted")
        } else if lowercaseOutput.contains("geo") && lowercaseOutput.contains("block") {
            return .geoBlocked("This video is not available in your region")
        } else if lowercaseOutput.contains("copyright") {
            return .copyrightRestricted("This video has copyright restrictions")
        } else if lowercaseOutput.contains("network") || lowercaseOutput.contains("connection") {
            return .networkError("Network connection error")
        } else {
            return .loadFailed("Failed to load video information: \(output)")
        }
    }

    func clearVideoInfo() {
        currentVideoInfo = nil
    }
}

// Thread-safe actor for buffering output
private actor OutputBuffer {
    private(set) var outputData = Data()

    func appendData(_ data: Data) {
        outputData.append(data)
    }
}

// Thread-safe actor for process state management (reused pattern)
private actor ProcessStateManager {
    private var hasResumed = false

    func markResumedAndCleanup(_ cleanup: @Sendable () -> Void) -> Bool {
        if hasResumed {
            return true
        }
        hasResumed = true
        cleanup()
        return false
    }
}

enum VideoInfoError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case invalidURL
    case videoNotFound(String)
    case videoUnavailable(String)
    case ageRestricted(String)
    case geoBlocked(String)
    case copyrightRestricted(String)
    case networkError(String)
    case timeout
    case parsingFailed(String)
    case processError(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(_):
            return "Setup required. Please configure required tools in Settings."
        case .invalidURL:
            return "Invalid YouTube URL. Please check the link and try again."
        case .videoNotFound(let message):
            return message
        case .videoUnavailable(let message):
            return message
        case .ageRestricted(let message):
            return message
        case .geoBlocked(let message):
            return message
        case .copyrightRestricted(let message):
            return message
        case .networkError(let message):
            return message
        case .timeout:
            return "Request timed out. Please try again."
        case .parsingFailed(let message):
            return "Failed to load video information: \(message)"
        case .processError(let message):
            return "Error loading video information: \(message)"
        case .loadFailed(let message):
            return message
        }
    }

    func toAppError() -> AppError {
        switch self {
        case .binaryNotFound(_):
            return .binaryNotFound("Setup required. Please configure required tools in Settings.")
        case .invalidURL:
            return .invalidInput("Invalid YouTube URL. Please check the link and try again.")
        case .videoNotFound(let message), .videoUnavailable(let message),
             .ageRestricted(let message), .geoBlocked(let message),
             .copyrightRestricted(let message):
            return .invalidInput(message)
        case .networkError(_):
            return .network("No internet connection. CutClip requires internet.")
        case .timeout:
            return .network("Request timed out. Please check your connection and try again.")
        case .parsingFailed(let message), .processError(let message), .loadFailed(let message):
            return .unknown("Failed to load video information: \(message)")
        }
    }
}