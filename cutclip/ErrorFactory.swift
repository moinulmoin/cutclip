//
//  ErrorFactory.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import Foundation

/// Factory for creating AppError instances with consistent messaging
/// Separates error creation logic from UI presentation concerns
enum ErrorFactory {
    
    // MARK: - Error Builders
    
    /// Generic error builder for common error patterns
    static func createError(
        type: AppError.ErrorType,
        context: ErrorContext,
        customMessage: String? = nil
    ) -> AppError {
        let message = customMessage ?? context.defaultMessage
        
        switch type {
        case .network:
            return .network(message)
        case .diskSpace:
            return .diskSpace(message)
        case .invalidInput:
            return .invalidInput(message)
        case .licenseError:
            return .licenseError(message)
        case .downloadFailed:
            return .downloadFailed(message)
        case .clippingFailed:
            return .clippingFailed(message)
        case .fileSystem:
            return .fileSystem(message)
        case .initialization:
            return .initialization(message)
        case .binaryNotFound:
            return .binaryNotFound(message)
        case .unknown:
            return .unknown(message)
        }
    }
    
    // MARK: - Network Errors
    
    static func noInternetError() -> AppError {
        createError(type: .network, context: .noInternet)
    }
    
    static func connectionLostError() -> AppError {
        createError(type: .network, context: .connectionLost)
    }
    
    static func serverError() -> AppError {
        createError(type: .network, context: .serverUnavailable)
    }
    
    static func requestFailedError() -> AppError {
        createError(type: .network, context: .requestFailed)
    }
    
    static func videoInfoTimeoutError() -> AppError {
        createError(type: .network, context: .videoInfoTimeout)
    }
    
    // MARK: - License Errors
    
    static func invalidLicenseError() -> AppError {
        createError(type: .licenseError, context: .invalidLicense)
    }
    
    static func licenseInUseError() -> AppError {
        createError(type: .licenseError, context: .licenseInUse)
    }
    
    static func licenseVerificationError() -> AppError {
        createError(type: .licenseError, context: .licenseVerificationFailed)
    }
    
    static func freeCreditsExhaustedError() -> AppError {
        createError(type: .licenseError, context: .freeCreditsExhausted)
    }
    
    // MARK: - Video Errors
    
    static func invalidURLError() -> AppError {
        createError(type: .invalidInput, context: .invalidYouTubeURL)
    }
    
    static func videoNotFoundError() -> AppError {
        createError(type: .invalidInput, context: .videoNotFound)
    }
    
    static func videoUnavailableError() -> AppError {
        createError(type: .invalidInput, context: .videoUnavailable)
    }
    
    static func videoAgeRestrictedError() -> AppError {
        createError(type: .invalidInput, context: .videoAgeRestricted)
    }
    
    static func videoGeoBlockedError() -> AppError {
        createError(type: .invalidInput, context: .videoGeoBlocked)
    }
    
    static func videoCopyrightError() -> AppError {
        createError(type: .invalidInput, context: .videoCopyright)
    }
    
    static func videoProcessingError() -> AppError {
        createError(type: .clippingFailed, context: .videoProcessingFailed)
    }
    
    static func videoSaveError() -> AppError {
        createError(type: .fileSystem, context: .videoSaveFailed)
    }
    
    static func videoInfoParsingError() -> AppError {
        createError(type: .unknown, context: .videoInfoParsing)
    }
    
    static func videoInfoLoadError() -> AppError {
        createError(type: .downloadFailed, context: .videoInfoLoad)
    }
    
    // MARK: - Setup Errors
    
    static func setupDownloadError() -> AppError {
        createError(type: .downloadFailed, context: .setupDownloadFailed)
    }
    
    static func setupInterruptedError() -> AppError {
        createError(type: .downloadFailed, context: .setupInterrupted)
    }
    
    static func setupDiskSpaceError() -> AppError {
        createError(type: .diskSpace, context: .setupDiskSpace)
    }
    
    // MARK: - System Errors
    
    static func diskSpaceError(requiredMB: Int, availableMB: Int) -> AppError {
        let message = "Insufficient disk space. Required: \(requiredMB)MB, Available: \(availableMB)MB"
        return createError(type: .diskSpace, context: .insufficientDiskSpace, customMessage: message)
    }
    
    static func fileSystemError(_ detail: String) -> AppError {
        createError(type: .fileSystem, context: .fileAccess, customMessage: "Unable to access file: \(detail)")
    }
    
    static func unknownError(_ detail: String) -> AppError {
        createError(type: .unknown, context: .unknown, customMessage: detail)
    }
}

// MARK: - Error Context

/// Predefined error contexts with default messages
enum ErrorContext {
    // Network
    case noInternet
    case connectionLost
    case serverUnavailable
    case requestFailed
    case videoInfoTimeout
    
    // License
    case invalidLicense
    case licenseInUse
    case licenseVerificationFailed
    case freeCreditsExhausted
    
    // Video
    case invalidYouTubeURL
    case videoNotFound
    case videoUnavailable
    case videoAgeRestricted
    case videoGeoBlocked
    case videoCopyright
    case videoProcessingFailed
    case videoSaveFailed
    case videoInfoParsing
    case videoInfoLoad
    
    // Setup
    case setupDownloadFailed
    case setupInterrupted
    case setupDiskSpace
    
    // System
    case insufficientDiskSpace
    case fileAccess
    case unknown
    
    var defaultMessage: String {
        switch self {
        // Network
        case .noInternet:
            return "No internet connection. CutClip requires internet."
        case .connectionLost:
            return "Connection lost. Please check your internet and try again."
        case .serverUnavailable:
            return "Server temporarily unavailable. Please try again in a moment."
        case .requestFailed:
            return "Request failed. Please check your connection and retry."
        case .videoInfoTimeout:
            return "Video info request timed out. Please check your connection and try again."
            
        // License
        case .invalidLicense:
            return "Invalid license key. Please check and try again."
        case .licenseInUse:
            return "License already in use on another device. Contact support if needed."
        case .licenseVerificationFailed:
            return "Unable to verify license. Check your internet connection."
        case .freeCreditsExhausted:
            return "Free clips used up. Enter a license key for unlimited clipping."
            
        // Video
        case .invalidYouTubeURL:
            return "Invalid YouTube URL. Please check the link and try again."
        case .videoNotFound:
            return "Video not found. Please check the YouTube URL and try again."
        case .videoUnavailable:
            return "This video is private or unavailable."
        case .videoAgeRestricted:
            return "This video is age-restricted and cannot be processed."
        case .videoGeoBlocked:
            return "This video is not available in your region."
        case .videoCopyright:
            return "This video has copyright restrictions."
        case .videoProcessingFailed:
            return "Video processing failed. This video may be restricted."
        case .videoSaveFailed:
            return "Unable to save video. Please check your disk space."
        case .videoInfoParsing:
            return "Failed to parse video information. Please try again."
        case .videoInfoLoad:
            return "Failed to load video information. Please check the URL and try again."
            
        // Setup
        case .setupDownloadFailed:
            return "Unable to download required tools. Please check your internet connection and try again."
        case .setupInterrupted:
            return "Download interrupted. Click 'Try Again' to continue setup."
        case .setupDiskSpace:
            return "Setup failed. Please ensure you have sufficient disk space and try again."
            
        // System
        case .insufficientDiskSpace:
            return "Insufficient disk space."
        case .fileAccess:
            return "Unable to access file."
        case .unknown:
            return "An unexpected error occurred."
        }
    }
}

// MARK: - AppError Extension

extension AppError {
    enum ErrorType {
        case network
        case diskSpace
        case invalidInput
        case binaryNotFound
        case downloadFailed
        case clippingFailed
        case fileSystem
        case licenseError
        case initialization
        case unknown
    }
}