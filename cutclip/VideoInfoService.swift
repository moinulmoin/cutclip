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
    private let processExecutor = ProcessExecutor()
    private var cacheService: VideoCacheService { VideoCacheService.shared }
    @Published var isLoading: Bool = false
    @Published var currentVideoInfo: VideoInfo?

    init(binaryManager: BinaryManager) {
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
        // Extract video ID for caching
        let videoId = ValidationUtils.extractYouTubeVideoID(urlString)
        
        // Check cache first
        if let videoId = videoId, let cachedInfo = cacheService.checkMetadataCache(videoId: videoId) {
            print("🎯 Using cached metadata for video \(videoId)")
            await MainActor.run {
                self.currentVideoInfo = cachedInfo
            }
            return cachedInfo
        }
        
        // Retry logic for first-run issues
        var lastError: Error?

        for attempt in 1...3 {
            do {
                let videoInfo = try await loadVideoInfoAttempt(for: urlString)
                
                // Save to cache after successful load
                if let videoId = videoId {
                    cacheService.saveMetadataToCache(videoId: videoId, videoInfo: videoInfo)
                }
                
                return videoInfo
            } catch let error as VideoInfoError {
                lastError = error

                // Only retry on parsing failures (which might be first-run issues)
                if case .parsingFailed(_) = error, attempt < 3 {
                    print("⚠️ VideoInfo attempt \(attempt) failed with parsing error, retrying...")
                    // Wait a bit before retry
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }

        throw lastError ?? VideoInfoError.parsingFailed("Failed after 3 attempts")
    }

    private func loadVideoInfoAttempt(for urlString: String) async throws -> VideoInfo {
        // Trust that AutoSetup has verified yt-dlp is functional
        // If we reached ClipperView, binaries should be ready
        let ytDlpPath = await MainActor.run { binaryManager.ytDlpPath }!
        
        await MainActor.run {
            self.isLoading = true
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }
        
        // Use --print with output template syntax
        let printFormat = """
        {"id":"%(id)s","title":"%(title)s","duration":%(duration|0)s,"thumbnail":"%(thumbnail|)s","uploader":"%(uploader|)s","upload_date":"%(upload_date|)s","view_count":%(view_count|0)s,"best_height":%(formats.-1.height|0)s}
        """
        
        let config = ProcessConfiguration(
            executablePath: ytDlpPath,
            arguments: [
                "--print", printFormat.trimmingCharacters(in: .whitespacesAndNewlines),
                "--no-playlist",
                "--no-warnings",
                "--skip-download",
                "--quiet",
                urlString
            ],
            timeout: 30
        )
        
        do {
            let result = try await processExecutor.execute(config)
            
            if result.isSuccess {
                print("📊 Output data size: \(result.output.count) bytes")
                
                if let outputString = result.outputString {
                    print("📊 Video info output: \(outputString)")
                }
                
                let videoInfo = try await self.parseVideoInfo(from: result.output)
                await MainActor.run {
                    self.currentVideoInfo = videoInfo
                }
                return videoInfo
            } else {
                let errorOutput = result.errorString ?? result.outputString ?? "Unknown error"
                let error = self.parseYtDlpError(from: errorOutput)
                throw error
            }
        } catch let error as ProcessExecutorError {
            switch error {
            case .timeout:
                throw VideoInfoError.timeout
            case .launchFailed(let message):
                throw VideoInfoError.processError(message)
            case .executionFailed(_, let errorMessage):
                if let errorMessage = errorMessage {
                    let error = self.parseYtDlpError(from: errorMessage)
                    throw error
                } else {
                    throw VideoInfoError.parsingFailed("Process failed with no error message")
                }
            }
        }
    }

    private nonisolated func parseVideoInfo(from data: Data) async throws -> VideoInfo {
        // Simple struct for the --print output
        struct MinimalVideoInfo: Codable {
            let id: String
            let title: String
            let duration: Int
            let thumbnail: String
            let uploader: String
            let upload_date: String
            let view_count: Int
            let best_height: Int
        }

        let decoder = JSONDecoder()

        do {
            let minimalInfo = try decoder.decode(MinimalVideoInfo.self, from: data)

            // Create default formats for common YouTube qualities
            let defaultFormats = createDefaultFormats()

            // Convert to full VideoInfo with default values for missing fields
            var videoInfo = VideoInfo(
                id: minimalInfo.id,
                title: minimalInfo.title,
                description: nil,
                duration: TimeInterval(minimalInfo.duration),
                thumbnailURL: minimalInfo.thumbnail.isEmpty ? nil : minimalInfo.thumbnail,
                channelName: minimalInfo.uploader.isEmpty ? nil : minimalInfo.uploader,
                uploadDate: minimalInfo.upload_date.isEmpty ? nil : minimalInfo.upload_date,
                viewCount: minimalInfo.view_count > 0 ? minimalInfo.view_count : nil,
                availableFormats: defaultFormats,
                availableCaptions: [],
                webpageURL: "https://www.youtube.com/watch?v=\(minimalInfo.id)"
            )

            // Set the actual best height from yt-dlp
            videoInfo.actualBestHeight = minimalInfo.best_height

            // Debug logging
            print("📊 Parsed video info - Title: \(videoInfo.title), Best Height: \(minimalInfo.best_height)p")

            return videoInfo
        } catch {
            print("❌ Failed to parse minimal video info: \(error)")
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

    // Create default video formats for common YouTube qualities
    private nonisolated func createDefaultFormats() -> [VideoFormat] {
        return [
            VideoFormat(
                formatID: "137",
                ext: "mp4",
                height: 1080,
                width: 1920,
                fps: 30.0,
                filesize: nil,
                formatNote: "1080p",
                vcodec: "h264",
                acodec: nil,
                quality: 1080
            ),
            VideoFormat(
                formatID: "22",
                ext: "mp4",
                height: 720,
                width: 1280,
                fps: 30.0,
                filesize: nil,
                formatNote: "720p",
                vcodec: "h264",
                acodec: "aac",
                quality: 720
            ),
            VideoFormat(
                formatID: "135",
                ext: "mp4",
                height: 480,
                width: 854,
                fps: 30.0,
                filesize: nil,
                formatNote: "480p",
                vcodec: "h264",
                acodec: nil,
                quality: 480
            ),
            VideoFormat(
                formatID: "134",
                ext: "mp4",
                height: 360,
                width: 640,
                fps: 30.0,
                filesize: nil,
                formatNote: "360p",
                vcodec: "h264",
                acodec: nil,
                quality: 360
            )
        ]
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
