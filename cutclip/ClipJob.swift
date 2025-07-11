//
//  ClipJob.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

struct ClipJob: Sendable {
    let id = UUID()
    let url: String
    let startTime: String
    let endTime: String
    let aspectRatio: AspectRatio
    /// Requested output quality (eg "360p", "720p", "Best")
    let quality: String
    let status: ClipStatus
    let progress: Double
    let downloadedFilePath: String?
    let outputFilePath: String?
    let errorMessage: String?
    let videoInfo: VideoInfo?

    init(url: String, startTime: String, endTime: String, aspectRatio: AspectRatio, quality: String = "Best", status: ClipStatus = .pending, progress: Double = 0.0, downloadedFilePath: String? = nil, outputFilePath: String? = nil, errorMessage: String? = nil, videoInfo: VideoInfo? = nil) {
        self.url = url
        self.startTime = startTime
        self.endTime = endTime
        self.aspectRatio = aspectRatio
        self.quality = quality
        self.status = status
        self.progress = progress
        self.downloadedFilePath = downloadedFilePath
        self.outputFilePath = outputFilePath
        self.errorMessage = errorMessage
        self.videoInfo = videoInfo
    }

    enum ClipStatus: Sendable {
        case pending
        case downloading
        case downloaded
        case clipping
        case completed
        case failed
    }

    enum AspectRatio: String, CaseIterable, Sendable {
        case original = "Auto"         // No crop
        case nineSixteen = "9:16"      // Vertical/TikTok/Stories
        case oneOne = "1:1"            // Square
        case fourThree = "4:3"         // Traditional TV/iPad

        var cropFilter: String? {
            switch self {
            case .original:
                return nil
            case .nineSixteen:
                // FFmpeg crop filter for 9:16 aspect ratio (vertical)
                // Escape commas inside min() functions for FFmpeg filter parsing
                return "crop=min(iw\\,ih*9/16):min(ih\\,iw*16/9):(iw-min(iw\\,ih*9/16))/2:(ih-min(ih\\,iw*16/9))/2"
            case .oneOne:
                // FFmpeg crop filter for 1:1 aspect ratio (square)
                return "crop=min(iw\\,ih):min(iw\\,ih):(iw-min(iw\\,ih))/2:(ih-min(iw\\,ih))/2"
            case .fourThree:
                // FFmpeg crop filter for 4:3 aspect ratio (traditional)
                return "crop=min(iw\\,ih*4/3):min(ih\\,iw*3/4):(iw-min(iw\\,ih*4/3))/2:(ih-min(ih\\,iw*3/4))/2"
            }
        }
        
        /// Returns target width for the given quality height
        func targetWidth(for quality: String) -> Int? {
            guard let height = Int(quality.lowercased().replacingOccurrences(of: "p", with: "")) else {
                return nil
            }
            
            switch self {
            case .original:
                return nil // Can't determine without source
            case .nineSixteen: // 9:16 vertical
                let width = Int(Double(height) * 9.0 / 16.0)
                // Ensure width is even for video encoding compatibility
                return width % 2 == 0 ? width : width + 1
            case .oneOne: // 1:1 square
                // Height might be odd, so ensure it's even
                return height % 2 == 0 ? height : height + 1
            case .fourThree: // 4:3 traditional
                let width = Int(Double(height) * 4.0 / 3.0)
                // Ensure width is even for video encoding compatibility
                return width % 2 == 0 ? width : width + 1
            }
        }
        
        /// Returns target height for the given quality
        func targetHeight(for quality: String) -> Int? {
            guard let height = Int(quality.lowercased().replacingOccurrences(of: "p", with: "")) else {
                return nil
            }
            // Ensure height is even for video encoding compatibility
            return height % 2 == 0 ? height : height + 1
        }
        
        /// Returns FFmpeg scale filter for the target resolution
        func scaleFilter(for quality: String) -> String? {
            guard let width = targetWidth(for: quality),
                  let height = targetHeight(for: quality) else {
                return nil
            }
            return "scale=\(width):\(height)"
        }
    }
}