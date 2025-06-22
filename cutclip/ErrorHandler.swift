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
                    throw AppError.network("Network connectivity issue (Status: \(httpResponse.statusCode))")
                }
            }
        } catch {
            if error is AppError {
                throw error
            } else {
                throw AppError.network("No internet connection or YouTube is unreachable")
            }
        }
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
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "Network Error: \(message)"
        case .diskSpace(let message):
            return "Disk Space Error: \(message)"
        case .invalidInput(let message):
            return "Invalid Input: \(message)"
        case .binaryNotFound(let message):
            return "Binary Not Found: \(message)"
        case .downloadFailed(let message):
            return "Download Failed: \(message)"
        case .clippingFailed(let message):
            return "Clipping Failed: \(message)"
        case .fileSystem(let message):
            return "File System Error: \(message)"
        case .unknown(let message):
            return "Unknown Error: \(message)"
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
        case .unknown:
            return "Please try again or restart the application."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .network, .downloadFailed, .clippingFailed, .unknown:
            return true
        case .diskSpace, .invalidInput, .binaryNotFound, .fileSystem:
            return false
        }
    }
}

// SwiftUI Error Alert View
struct ErrorAlertView: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $errorHandler.showingAlert) {
                Button("OK") {
                    errorHandler.clearError()
                }
                if errorHandler.currentError?.isRetryable == true {
                    Button("Retry") {
                        errorHandler.clearError()
                        // Retry logic would be handled by the calling view
                    }
                }
            } message: {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = errorHandler.currentError {
                        Text(error.localizedDescription)
                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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