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
    
    init(url: String, startTime: String, endTime: String, aspectRatio: AspectRatio, status: ClipStatus = .pending, progress: Double = 0.0, downloadedFilePath: String? = nil, outputFilePath: String? = nil, errorMessage: String? = nil) {
        self.url = url
        self.startTime = startTime
        self.endTime = endTime
        self.aspectRatio = aspectRatio
        self.status = status
        self.progress = progress
        self.downloadedFilePath = downloadedFilePath
        self.outputFilePath = outputFilePath
        self.errorMessage = errorMessage
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
        
        var cropFilter: String? {
            switch self {
            case .original:
                return nil
            case .sixteenNine:
                return "crop=iw:iw*9/16:(iw-iw)/2:(ih-iw*9/16)/2"
            case .oneOne:
                return "crop=min(iw\\,ih):min(iw\\,ih):(iw-min(iw\\,ih))/2:(ih-min(iw\\,ih))/2"
            }
        }
    }
}