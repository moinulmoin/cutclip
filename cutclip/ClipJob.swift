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
    let status: ClipStatus
    let progress: Double
    let downloadedFilePath: String?
    let outputFilePath: String?
    let errorMessage: String?
    let videoInfo: VideoInfo?
    
    init(url: String, startTime: String, endTime: String, aspectRatio: AspectRatio, status: ClipStatus = .pending, progress: Double = 0.0, downloadedFilePath: String? = nil, outputFilePath: String? = nil, errorMessage: String? = nil, videoInfo: VideoInfo? = nil) {
        self.url = url
        self.startTime = startTime
        self.endTime = endTime
        self.aspectRatio = aspectRatio
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
        case original = "Original"
        case sixteenNine = "16:9"
        case oneOne = "1:1"
        case nineSixteen = "9:16"      // Vertical/TikTok/Stories
        case fourThree = "4:3"         // Traditional TV/iPad
        case twentyOneNine = "21:9"    // Ultrawide/Cinematic
        case threeFour = "3:4"         // Portrait format
        
        var cropFilter: String? {
            switch self {
            case .original:
                return nil
            case .sixteenNine:
                return "crop=min(iw\\,ih*16/9):min(ih\\,iw*9/16):(iw-min(iw\\,ih*16/9))/2:(ih-min(ih\\,iw*9/16))/2"
            case .oneOne:
                return "crop=min(iw\\,ih):min(iw\\,ih):(iw-min(iw\\,ih))/2:(ih-min(iw\\,ih))/2"
            case .nineSixteen:
                return "crop=min(iw\\,ih*9/16):min(ih\\,iw*16/9):(iw-min(iw\\,ih*9/16))/2:(ih-min(ih\\,iw*16/9))/2"
            case .fourThree:
                return "crop=min(iw\\,ih*4/3):min(ih\\,iw*3/4):(iw-min(iw\\,ih*4/3))/2:(ih-min(ih\\,iw*3/4))/2"
            case .twentyOneNine:
                return "crop=min(iw\\,ih*21/9):min(ih\\,iw*9/21):(iw-min(iw\\,ih*21/9))/2:(ih-min(ih\\,iw*9/21))/2"
            case .threeFour:
                return "crop=min(iw\\,ih*3/4):min(ih\\,iw*4/3):(iw-min(iw\\,ih*3/4))/2:(ih-min(ih\\,iw*4/3))/2"
            }
        }
    }
}