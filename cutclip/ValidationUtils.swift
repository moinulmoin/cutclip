//
//  ValidationUtils.swift
//  cutclip
//
//  Created by Moinul Moin on 6/24/25.
//

import Foundation

/// Centralized validation utilities for consistent input validation
struct ValidationUtils {

    // MARK: - URL Validation

    /// Validates YouTube URL format
    static func isValidYouTubeURL(_ urlString: String) -> Bool {
        let patterns = [
            "^https?://(?:www\\.)?youtube\\.com/watch\\?v=([a-zA-Z0-9_-]{11})",
            "^https?://(?:www\\.)?youtu\\.be/([a-zA-Z0-9_-]{11})",
            "^https?://(?:www\\.)?youtube\\.com/embed/([a-zA-Z0-9_-]{11})",
            "^https?://(?:m\\.)?youtube\\.com/watch\\?v=([a-zA-Z0-9_-]{11})"
        ]

        return patterns.contains { pattern in
            urlString.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Extracts YouTube video ID from URL
    static func extractYouTubeVideoID(_ urlString: String) -> String? {
        let patterns = [
            "(?:youtube\\.com/watch\\?v=|youtu\\.be/|youtube\\.com/embed/)([a-zA-Z0-9_-]{11})"
        ]

        for pattern in patterns {
            if let range = urlString.range(of: pattern, options: .regularExpression) {
                let match = String(urlString[range])
                return String(match.suffix(11))
            }
        }
        return nil
    }

    // MARK: - Time Format Validation

    /// Validates time format (HH:MM:SS)
    static func isValidTimeFormat(_ timeString: String) -> Bool {
        let pattern = "^([0-1]?[0-9]|2[0-3]):([0-5]?[0-9]):([0-5]?[0-9])$"
        return timeString.range(of: pattern, options: .regularExpression) != nil
    }

    /// Converts time string to seconds
    static func timeStringToSeconds(_ timeString: String) -> Int? {
        guard isValidTimeFormat(timeString) else { return nil }

        let components = timeString.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }

        let hours = components[0]
        let minutes = components[1]
        let seconds = components[2]

        return hours * 3600 + minutes * 60 + seconds
    }

    /// Converts seconds to time string (HH:MM:SS)
    static func secondsToTimeString(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Validates that start time is before end time
    static func isValidTimeRange(start: String, end: String) -> Bool {
        guard let startSeconds = timeStringToSeconds(start),
              let endSeconds = timeStringToSeconds(end) else {
            return false
        }

        return startSeconds < endSeconds
    }

    // MARK: - License Key Validation

    /// Validates license key format (lenient)
    static func isValidLicenseKeyFormat(_ licenseKey: String) -> Bool {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check for minimum length
        guard trimmed.count >= 8 else { return false }

        // 2. Allow only alphanumeric characters and hyphens
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard trimmed.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return false
        }

        return true
    }

    /// Sanitizes license key input
    static func sanitizeLicenseKey(_ licenseKey: String) -> String {
        return licenseKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    // MARK: - Video Quality Validation

    /// Available video quality options
    static let availableQualities = ["360p", "480p", "720p", "1080p", "Best"]

    /// Validates video quality selection
    static func isValidQuality(_ quality: String) -> Bool {
        return availableQualities.contains(quality)
    }

    // MARK: - File Path Validation

    /// Validates that file path is safe and writable
    static func isValidOutputPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let parentDirectory = url.deletingLastPathComponent()

        return FileManager.default.isWritableFile(atPath: parentDirectory.path)
    }

    // MARK: - Video Info Validation

    /// Validates video info data completeness
    static func isValidVideoInfo(_ videoInfo: VideoInfo) -> Bool {
        // Basic validation - ensure essential fields are present
        guard !videoInfo.id.isEmpty,
              !videoInfo.title.isEmpty,
              videoInfo.duration > 0 else {
            return false
        }

        // Validate available formats
        guard !videoInfo.availableFormats.isEmpty else {
            return false
        }

        return true
    }

    /// Validates video format data
    static func isValidVideoFormat(_ format: VideoFormat) -> Bool {
        // Ensure format has valid identifier and extension
        guard !format.formatID.isEmpty,
              !format.ext.isEmpty else {
            return false
        }

        // If it's a video format, it should have height
        if format.isVideoFormat && format.height == nil {
            return false
        }

        return true
    }

    /// Validates that a quality string matches available formats
    static func isValidQualityForVideoInfo(_ quality: String, videoInfo: VideoInfo) -> Bool {
        if quality == "Best" {
            return true
        }

        return videoInfo.qualityOptions.contains(quality)
    }

    /// Extracts numeric quality from quality string (e.g., "720p" -> 720)
    static func extractQualityHeight(_ quality: String) -> Int? {
        guard quality != "Best" else { return nil }
        
        // Remove 'p' suffix and convert to integer
        let numericString = quality.replacingOccurrences(of: "p", with: "")
        return Int(numericString)
    }

    /// Finds the best format for a given quality preference
    static func findBestFormat(for quality: String, in videoInfo: VideoInfo) -> VideoFormat? {
        let formats = videoInfo.availableFormats.filter { $0.isVideoFormat }
        
        if quality == "Best" {
            // Return highest quality format
            return formats.max { ($0.height ?? 0) < ($1.height ?? 0) }
        }
        
        guard let targetHeight = extractQualityHeight(quality) else {
            return nil
        }
        
        // Find exact match first
        if let exactMatch = formats.first(where: { $0.height == targetHeight }) {
            return exactMatch
        }
        
        // If no exact match, find closest lower quality
        let lowerQualities = formats.filter { ($0.height ?? 0) <= targetHeight }
        return lowerQualities.max { ($0.height ?? 0) < ($1.height ?? 0) }
    }

    /// Validates caption track data
    static func isValidCaptionTrack(_ caption: CaptionTrack) -> Bool {
        return !caption.language.isEmpty && !caption.languageCode.isEmpty
    }

    /// Checks if video has captions in a specific language
    static func hasCaption(for languageCode: String, in videoInfo: VideoInfo) -> Bool {
        return videoInfo.availableCaptions.contains { $0.languageCode == languageCode }
    }

    /// Validates duration is within reasonable bounds
    static func isValidVideoDuration(_ duration: TimeInterval) -> Bool {
        // Duration should be positive and not exceed reasonable limits (12 hours)
        return duration > 0 && duration <= 43200
    }

    /// Checks if clip time range is valid for video duration
    static func isValidClipRange(start: String, end: String, videoDuration: TimeInterval) -> Bool {
        guard let startSeconds = timeStringToSeconds(start),
              let endSeconds = timeStringToSeconds(end) else {
            return false
        }

        // Check basic time range validity
        guard startSeconds < endSeconds else {
            return false
        }

        // Check that end time doesn't exceed video duration
        guard Double(endSeconds) <= videoDuration else {
            return false
        }

        return true
    }

    // MARK: - Error Messages

    enum ValidationError: LocalizedError {
        case invalidYouTubeURL
        case invalidTimeFormat
        case invalidTimeRange
        case invalidLicenseKey
        case invalidQuality
        case invalidOutputPath
        case invalidVideoInfo
        case invalidVideoFormat
        case invalidVideoDuration
        case invalidClipRange
        case qualityNotAvailable

        var errorDescription: String? {
            switch self {
            case .invalidYouTubeURL:
                return "Please enter a valid YouTube URL"
            case .invalidTimeFormat:
                return "Time format must be HH:MM:SS"
            case .invalidTimeRange:
                return "Start time must be before end time"
            case .invalidLicenseKey:
                return "License key format is invalid"
            case .invalidQuality:
                return "Selected quality is not supported"
            case .invalidOutputPath:
                return "Output path is not writable"
            case .invalidVideoInfo:
                return "Video information is incomplete or invalid"
            case .invalidVideoFormat:
                return "Video format is not supported"
            case .invalidVideoDuration:
                return "Video duration is invalid"
            case .invalidClipRange:
                return "Clip time range exceeds video duration"
            case .qualityNotAvailable:
                return "Selected quality is not available for this video"
            }
        }
    }
}