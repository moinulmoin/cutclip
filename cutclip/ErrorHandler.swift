//
//  ErrorHandler.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation
import SwiftUI
import AppKit

/// Legacy error handler maintained for backward compatibility
/// New code should use ErrorPresenter for UI and ErrorFactory for error creation
@MainActor
class ErrorHandler: ObservableObject {
    // Internal presenter handles all UI concerns
    internal let presenter = ErrorPresenter()
    
    // Published properties for backward compatibility
    @Published var currentError: AppError? {
        didSet {
            presenter.currentError = currentError
        }
    }
    @Published var showingAlert: Bool = false {
        didSet {
            presenter.showingAlert = showingAlert
        }
    }
    @Published var showingInitSheet: Bool = false {
        didSet {
            presenter.showingInitSheet = showingInitSheet
        }
    }
    
    var retryAction: (() -> Void)? {
        get { presenter.retryAction }
        set { presenter.retryAction = newValue }
    }
    
    var quitAction: (() -> Void)? {
        get { presenter.quitAction }
        set { presenter.quitAction = newValue }
    }
    
    var isInitializationError: Bool {
        get { presenter.isInitializationError }
        set { presenter.isInitializationError = newValue }
    }
    
    var alertID: UUID {
        get { presenter.alertID }
        set { presenter.alertID = newValue }
    }
    
    init() {
        // Sync presenter state changes back to this class
        presenter.$currentError
            .assign(to: &$currentError)
        presenter.$showingAlert
            .assign(to: &$showingAlert)
        presenter.$showingInitSheet
            .assign(to: &$showingInitSheet)
    }
    
    // MARK: - Legacy Methods (Delegating to Presenter)
    
    func handle(_ error: Error, retryAction: (() -> Void)? = nil) {
        presenter.presentError(error, retryAction: retryAction)
    }
    
    func showError(_ error: AppError, retryAction: (() -> Void)? = nil, isInitialization: Bool = false) {
        presenter.present(error, retryAction: retryAction, isInitialization: isInitialization)
    }
    
    func clearError() {
        presenter.clearError()
    }
    
    func handleNetworkError(_ error: Error, retryAction: (() -> Void)? = nil, isInitialization: Bool = false) {
        presenter.presentNetworkError(error, retryAction: retryAction, isInitialization: isInitialization)
    }
    
    // MARK: - Static Factory Methods (Delegating to ErrorFactory)
    // These are maintained for backward compatibility
    
    nonisolated static func checkDiskSpace(requiredMB: Int = 500) throws {
        try ErrorValidation.checkDiskSpace(requiredMB: requiredMB)
    }
    
    nonisolated static func checkNetworkConnectivity() async throws {
        try await ErrorValidation.checkNetworkConnectivity()
    }
    
    nonisolated static func createNoInternetError() -> AppError {
        ErrorFactory.noInternetError()
    }
    
    nonisolated static func createConnectionLostError() -> AppError {
        ErrorFactory.connectionLostError()
    }
    
    nonisolated static func createServerError() -> AppError {
        ErrorFactory.serverError()
    }
    
    nonisolated static func createRequestFailedError() -> AppError {
        ErrorFactory.requestFailedError()
    }
    
    nonisolated static func createInvalidLicenseError() -> AppError {
        ErrorFactory.invalidLicenseError()
    }
    
    nonisolated static func createLicenseInUseError() -> AppError {
        ErrorFactory.licenseInUseError()
    }
    
    nonisolated static func createLicenseVerificationError() -> AppError {
        ErrorFactory.licenseVerificationError()
    }
    
    nonisolated static func createFreeCreditsExhaustedError() -> AppError {
        ErrorFactory.freeCreditsExhaustedError()
    }
    
    nonisolated static func createInvalidURLError() -> AppError {
        ErrorFactory.invalidURLError()
    }
    
    nonisolated static func createVideoProcessingError() -> AppError {
        ErrorFactory.videoProcessingError()
    }
    
    nonisolated static func createVideoSaveError() -> AppError {
        ErrorFactory.videoSaveError()
    }
    
    nonisolated static func createSetupDownloadError() -> AppError {
        ErrorFactory.setupDownloadError()
    }
    
    nonisolated static func createSetupInterruptedError() -> AppError {
        ErrorFactory.setupInterruptedError()
    }
    
    nonisolated static func createSetupDiskSpaceError() -> AppError {
        ErrorFactory.setupDiskSpaceError()
    }
    
    nonisolated static func createVideoInfoTimeoutError() -> AppError {
        ErrorFactory.videoInfoTimeoutError()
    }
    
    nonisolated static func createVideoNotFoundError() -> AppError {
        ErrorFactory.videoNotFoundError()
    }
    
    nonisolated static func createVideoUnavailableError() -> AppError {
        ErrorFactory.videoUnavailableError()
    }
    
    nonisolated static func createVideoAgeRestrictedError() -> AppError {
        ErrorFactory.videoAgeRestrictedError()
    }
    
    nonisolated static func createVideoGeoBlockedError() -> AppError {
        ErrorFactory.videoGeoBlockedError()
    }
    
    nonisolated static func createVideoCopyrightError() -> AppError {
        ErrorFactory.videoCopyrightError()
    }
    
    nonisolated static func createVideoInfoParsingError() -> AppError {
        ErrorFactory.videoInfoParsingError()
    }
    
    nonisolated static func createVideoInfoLoadError() -> AppError {
        ErrorFactory.videoInfoLoadError()
    }
}

// MARK: - AppError Definition

enum AppError: LocalizedError, Equatable, Sendable {
    case network(String)
    case diskSpace(String)
    case invalidInput(String)
    case binaryNotFound(String)
    case downloadFailed(String)
    case clippingFailed(String)
    case fileSystem(String)
    case licenseError(String)
    case initialization(String)
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
        case .initialization:
            return "Startup Failed"
        case .unknown:
            return "Something Went Wrong"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .network(let message),
             .diskSpace(let message),
             .invalidInput(let message),
             .binaryNotFound(let message),
             .downloadFailed(let message),
             .clippingFailed(let message),
             .fileSystem(let message),
             .licenseError(let message),
             .initialization(let message),
             .unknown(let message):
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
        case .initialization:
            return "Please restart the application."
        case .unknown:
            return "Please try again or restart the application."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .network, .downloadFailed, .clippingFailed, .unknown:
            return true
        case .diskSpace, .invalidInput, .binaryNotFound, .fileSystem, .licenseError, .initialization:
            return false
        }
    }
}

// MARK: - Legacy View Modifier

struct ErrorAlertView: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler
    
    func body(content: Content) -> some View {
        content
            .errorPresenter(errorHandler.presenter)
    }
}

extension View {
    func errorAlert(_ errorHandler: ErrorHandler) -> some View {
        modifier(ErrorAlertView(errorHandler: errorHandler))
    }
}