//
//  ErrorHandler.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation
import SwiftUI

@MainActor
class ErrorHandler: ObservableObject {
    @Published var currentError: AppError?
    @Published var showingAlert = false
    
    func handle(_ error: Error) {
        if let appError = error as? AppError {
            self.currentError = appError
        } else {
            self.currentError = AppError.unknown(error.localizedDescription)
        }
        self.showingAlert = true
    }
    
    func clearError() {
        currentError = nil
        showingAlert = false
    }
    
    // System checks
    nonisolated static func checkDiskSpace(requiredMB: Int = 500) throws {
        guard let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw AppError.diskSpace("Cannot access Downloads directory")
        }
        
        do {
            let resourceValues = try downloadsPath.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacity {
                let availableMB = availableCapacity / (1024 * 1024)
                if availableMB < requiredMB {
                    throw AppError.diskSpace("Insufficient disk space. Required: \(requiredMB)MB, Available: \(availableMB)MB")
                }
            }
        } catch {
            if error is AppError {
                throw error
            } else {
                throw AppError.diskSpace("Unable to check disk space: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated static func checkNetworkConnectivity() async throws {
        let url = URL(string: "https://www.youtube.com")!
        let request = URLRequest(url: url, timeoutInterval: 10.0)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    throw AppError.network("Server temporarily unavailable. Please try again in a moment.")
                }
            }
        } catch {
            if error is AppError {
                throw error
            } else {
                throw AppError.network("No internet connection. CutClip requires internet.")
            }
        }
    }
    
    // MARK: - User-Friendly Error Helpers
    
    nonisolated static func createNoInternetError() -> AppError {
        return AppError.network("No internet connection. CutClip requires internet.")
    }
    
    nonisolated static func createConnectionLostError() -> AppError {
        return AppError.network("Connection lost. Please check your internet and try again.")
    }
    
    nonisolated static func createServerError() -> AppError {
        return AppError.network("Server temporarily unavailable. Please try again in a moment.")
    }
    
    nonisolated static func createRequestFailedError() -> AppError {
        return AppError.network("Request failed. Please check your connection and retry.")
    }
    
    nonisolated static func createInvalidLicenseError() -> AppError {
        return AppError.licenseError("Invalid license key. Please check and try again.")
    }
    
    nonisolated static func createLicenseInUseError() -> AppError {
        return AppError.licenseError("License already in use on another device. Contact support if needed.")
    }
    
    nonisolated static func createLicenseVerificationError() -> AppError {
        return AppError.licenseError("Unable to verify license. Check your internet connection.")
    }
    
    nonisolated static func createFreeCreditsExhaustedError() -> AppError {
        return AppError.licenseError("Free clips used up. Enter a license key for unlimited clipping.")
    }
    
    nonisolated static func createInvalidURLError() -> AppError {
        return AppError.invalidInput("Invalid YouTube URL. Please check the link and try again.")
    }
    
    nonisolated static func createVideoProcessingError() -> AppError {
        return AppError.clippingFailed("Video processing failed. This video may be restricted.")
    }
    
    nonisolated static func createVideoSaveError() -> AppError {
        return AppError.fileSystem("Unable to save video. Please check your disk space.")
    }
    
    nonisolated static func createSetupDownloadError() -> AppError {
        return AppError.downloadFailed("Unable to download required tools. Please check your internet connection and try again.")
    }
    
    nonisolated static func createSetupInterruptedError() -> AppError {
        return AppError.downloadFailed("Download interrupted. Click 'Try Again' to continue setup.")
    }
    
    nonisolated static func createSetupDiskSpaceError() -> AppError {
        return AppError.diskSpace("Setup failed. Please ensure you have sufficient disk space and try again.")
    }
    
    nonisolated static func validateTimeInputs(startTime: String, endTime: String) throws {
        // Validate format
        let timePattern = #"^\d{2}:\d{2}:\d{2}$"#
        let regex = try NSRegularExpression(pattern: timePattern)
        
        let startRange = NSRange(startTime.startIndex..<startTime.endIndex, in: startTime)
        let endRange = NSRange(endTime.startIndex..<endTime.endIndex, in: endTime)
        
        guard regex.firstMatch(in: startTime, range: startRange) != nil else {
            throw AppError.invalidInput("Start time must be in HH:MM:SS format")
        }
        
        guard regex.firstMatch(in: endTime, range: endRange) != nil else {
            throw AppError.invalidInput("End time must be in HH:MM:SS format")
        }
        
        // Convert to seconds and validate logic
        let startSeconds = timeToSeconds(startTime)
        let endSeconds = timeToSeconds(endTime)
        
        guard startSeconds < endSeconds else {
            throw AppError.invalidInput("End time must be after start time")
        }
        
        guard endSeconds - startSeconds >= 1 else {
            throw AppError.invalidInput("Clip must be at least 1 second long")
        }
        
        // Reasonable clip length limit (30 minutes)
        guard endSeconds - startSeconds <= 1800 else {
            throw AppError.invalidInput("Clip cannot be longer than 30 minutes")
        }
    }
    
    nonisolated private static func timeToSeconds(_ timeString: String) -> Double {
        let components = timeString.split(separator: ":").compactMap { Double($0) }
        guard components.count == 3 else { return 0 }
        return components[0] * 3600 + components[1] * 60 + components[2]
    }
}

enum AppError: LocalizedError, Equatable, Sendable {
    case network(String)
    case diskSpace(String)
    case invalidInput(String)
    case binaryNotFound(String)
    case downloadFailed(String)
    case clippingFailed(String)
    case fileSystem(String)
    case licenseError(String)
    case unknown(String)
    
    var errorTitle: String {
        switch self {
        case .network:
            return "Connection Issue"
        case .diskSpace:
            return "Storage Full"
        case .invalidInput:
            return "Invalid Input"
        case .binaryNotFound:
            return "Setup Required"
        case .downloadFailed:
            return "Download Failed"
        case .clippingFailed:
            return "Processing Failed"
        case .fileSystem:
            return "File Access Error"
        case .licenseError:
            return "License Required"
        case .unknown:
            return "Something Went Wrong"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .network(let message):
            return message
        case .diskSpace(let message):
            return message
        case .invalidInput(let message):
            return message
        case .binaryNotFound(let message):
            return message
        case .downloadFailed(let message):
            return message
        case .clippingFailed(let message):
            return message
        case .fileSystem(let message):
            return message
        case .licenseError(let message):
            return message
        case .unknown(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .network:
            return "Check your internet connection and try again."
        case .diskSpace:
            return "Free up some disk space and try again."
        case .invalidInput:
            return "Please correct the input and try again."
        case .binaryNotFound:
            return "Configure the required binaries in Settings."
        case .downloadFailed:
            return "Check the YouTube URL and your internet connection."
        case .clippingFailed:
            return "Verify the time inputs and try again."
        case .fileSystem:
            return "Check file permissions and available disk space."
        case .licenseError:
            return "Please enter a valid license key or wait for your trial credits to reset."
        case .unknown:
            return "Please try again or restart the application."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .network, .downloadFailed, .clippingFailed, .unknown:
            return true
        case .diskSpace, .invalidInput, .binaryNotFound, .fileSystem, .licenseError:
            return false
        }
    }
}

// SwiftUI Error Alert View
struct ErrorAlertView: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler
    
    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.errorTitle ?? "Error",
                isPresented: $errorHandler.showingAlert,
                presenting: errorHandler.currentError
            ) { error in
                Button("Dismiss", role: .cancel) {
                    errorHandler.clearError()
                }
                
                if error.isRetryable {
                    Button("Retry") {
                        errorHandler.clearError()
                        // Retry logic would be handled by the calling view
                    }
                }
            } message: { error in
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.errorDescription ?? "An unknown error occurred")
                        .font(.callout)
                    
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }
}

extension View {
    func errorAlert(_ errorHandler: ErrorHandler) -> some View {
        modifier(ErrorAlertView(errorHandler: errorHandler))
    }
}