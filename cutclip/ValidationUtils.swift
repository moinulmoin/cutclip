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
    
    /// Validates license key format
    static func isValidLicenseKey(_ licenseKey: String) -> Bool {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic format validation - adjust pattern as needed
        let pattern = "^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
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
    
    // MARK: - Error Messages
    
    enum ValidationError: LocalizedError {
        case invalidYouTubeURL
        case invalidTimeFormat
        case invalidTimeRange
        case invalidLicenseKey
        case invalidQuality
        case invalidOutputPath
        
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
            }
        }
    }
}