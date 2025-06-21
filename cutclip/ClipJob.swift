//
//  ClipJob.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

struct ClipJob {
    let id = UUID()
    let url: String
    let startTime: String
    let endTime: String
    let aspectRatio: AspectRatio
    var status: ClipStatus = .pending
    var progress: Double = 0.0
    var downloadedFilePath: String?
    var outputFilePath: String?
    var errorMessage: String?
    
    enum ClipStatus {
        case pending
        case downloading
        case downloaded
        case clipping
        case completed
        case failed
    }
    
    enum AspectRatio: String, CaseIterable {
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