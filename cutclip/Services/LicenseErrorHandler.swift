//
//  LicenseErrorHandler.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Handles error processing and user messaging for license operations
@MainActor
class LicenseErrorHandler {
    private let networkMonitor: NetworkMonitor
    weak var errorHandler: ErrorHandler?
    
    // Callbacks for state updates
    var onNetworkError: (@MainActor @Sendable (Bool) -> Void)?
    var onErrorMessage: (@MainActor @Sendable (String?) -> Void)?
    var onRetryAction: (@MainActor @Sendable () -> Void)?
    
    init(networkMonitor: NetworkMonitor, errorHandler: ErrorHandler? = nil) {
        self.networkMonitor = networkMonitor
        self.errorHandler = errorHandler
    }
    
    /// Process initialization errors and show appropriate user messages
    func handleInitializationError(_ error: Error) async {
        print("❌ Failed to initialize license system: \(error)")
        
        if let usageError = error as? UsageError {
            await handleUsageError(usageError, isInitialization: true)
        } else {
            await handleGenericError(error, isInitialization: true)
        }
    }
    
    /// Process license validation errors
    func handleLicenseValidationError(_ error: Error) -> String {
        if let usageError = error as? UsageError {
            return usageError.localizedDescription
        } else {
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Helpers
    
    private func handleUsageError(_ error: UsageError, isInitialization: Bool) async {
        onNetworkError?(true)
        let errorMessage: String
        
        switch error {
        case .networkError:
            // Use NetworkMonitor to check if it's device or server issue
            errorMessage = networkMonitor.isConnected ? 
                "Could not connect to CutClip servers." : 
                "No internet connection. Please check your network settings."
                
        case .serverError(let code) where code >= 500:
            errorMessage = "Server temporarily unavailable. Please try again in a moment."
            
        case .serverError(_):
            errorMessage = "Unable to connect to CutClip servers. Please check your connection."
            
        case .invalidResponse, .decodingError:
            errorMessage = "Server communication error. Please try again later."
            
        default:
            // Non-network errors don't set hasNetworkError
            onNetworkError?(false)
            onErrorMessage?("Failed to initialize CutClip. Please restart the app.")
            return
        }
        
        // Show error to user if handler available
        if let handler = errorHandler {
            handler.showError(
                AppError.network(errorMessage),
                retryAction: { [weak self] in
                    self?.onRetryAction?()
                },
                isInitialization: isInitialization
            )
        }
    }
    
    private func handleGenericError(_ error: Error, isInitialization: Bool) async {
        // For other errors, use NetworkMonitor's diagnosis
        let diagnosis = networkMonitor.diagnoseNetworkError(error)
        
        switch diagnosis {
        case .noInternetConnection, .serverUnreachable, .serverTimeout, .connectionLost:
            onNetworkError?(true)
            if let handler = errorHandler {
                handler.showError(
                    AppError.network(diagnosis.userMessage),
                    retryAction: { [weak self] in
                        self?.onRetryAction?()
                    },
                    isInitialization: isInitialization
                )
            }
            
        case .serverError(let message):
            onNetworkError?(true)
            if let handler = errorHandler {
                handler.showError(
                    AppError.network("Server error: \(message)"),
                    retryAction: { [weak self] in
                        self?.onRetryAction?()
                    },
                    isInitialization: isInitialization
                )
            }
            
        case .unknownError(_):
            onErrorMessage?("Failed to initialize CutClip. Please restart the app.")
        }
    }
    
    /// Determine if license setup is required based on error type
    func shouldRequireLicenseSetup(hasNetworkError: Bool) -> Bool {
        // Only require license setup if it's not a network error
        // For network errors, try to allow app to function with cached data
        return !hasNetworkError
    }
}