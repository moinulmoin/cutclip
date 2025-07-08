//
//  ErrorPresenter.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import SwiftUI
import AppKit

/// Handles the presentation of errors to the user
/// Manages alert/sheet display logic and UI concerns
@MainActor
class ErrorPresenter: ObservableObject {
    @Published var currentError: AppError?
    @Published var showingAlert = false
    @Published var showingInitSheet = false
    
    var retryAction: (() -> Void)?
    var quitAction: (() -> Void)?
    var isInitializationError = false
    var alertID = UUID()
    
    /// Present an error to the user
    func present(
        _ error: AppError,
        retryAction: (() -> Void)? = nil,
        isInitialization: Bool = false
    ) {
        // If an alert is already showing, don't override it immediately
        guard !showingAlert && !showingInitSheet else {
            print("⚠️ ErrorPresenter.present - alert already showing, ignoring new error: \(error.errorTitle)")
            return
        }
        
        alertID = UUID()
        print("🚨 ErrorPresenter.present - alertID: \(alertID), error: \(error.errorTitle), isInitialization: \(isInitialization), isRetryable: \(error.isRetryable)")
        
        self.currentError = error
        self.retryAction = retryAction
        self.isInitializationError = isInitialization
        
        if isInitialization {
            self.quitAction = {
                NSApplication.shared.terminate(nil)
            }
            // Use sheet for initialization errors to avoid automatic Cancel button
            self.showingInitSheet = true
        } else {
            // Use alert for normal errors
            self.showingAlert = true
        }
    }
    
    /// Present an error from any Error type
    func presentError(
        _ error: Error,
        retryAction: (() -> Void)? = nil,
        isInitialization: Bool = false
    ) {
        let appError = error as? AppError ?? AppError.unknown(error.localizedDescription)
        present(appError, retryAction: retryAction, isInitialization: isInitialization)
    }
    
    /// Enhanced network error presentation using NetworkMonitor
    func presentNetworkError(
        _ error: Error,
        retryAction: (() -> Void)? = nil,
        isInitialization: Bool = false
    ) {
        let diagnosis = NetworkMonitor.shared.diagnoseNetworkError(error)
        
        // Create appropriate AppError based on diagnosis
        let appError: AppError
        switch diagnosis {
        case .noInternetConnection:
            appError = ErrorFactory.noInternetError()
        case .serverUnreachable, .serverTimeout:
            appError = ErrorFactory.serverError()
        case .connectionLost:
            appError = ErrorFactory.connectionLostError()
        case .serverError(let message):
            appError = .network("Server error: \(message)")
        case .unknownError(let message):
            appError = .unknown(message)
        }
        
        // Show error with appropriate options
        present(
            appError,
            retryAction: diagnosis.isRetryable ? retryAction : nil,
            isInitialization: isInitialization
        )
    }
    
    /// Clear the current error state
    func clearError() {
        currentError = nil
        showingAlert = false
        showingInitSheet = false
        retryAction = nil
        quitAction = nil
        isInitializationError = false
    }
}

// MARK: - SwiftUI View Modifier

struct ErrorPresenterModifier: ViewModifier {
    @ObservedObject var presenter: ErrorPresenter
    
    func body(content: Content) -> some View {
        content
            // Normal errors use alert
            .alert(
                presenter.currentError?.errorTitle ?? "Error",
                isPresented: $presenter.showingAlert
            ) {
                Button("OK", role: .cancel) {
                    presenter.clearError()
                }
                if let error = presenter.currentError, error.isRetryable {
                    Button("Retry") {
                        let retryAction = presenter.retryAction
                        presenter.clearError()
                        retryAction?()
                    }
                }
            } message: {
                if let error = presenter.currentError {
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
            // Initialization errors use sheet to avoid automatic Cancel button
            .sheet(isPresented: $presenter.showingInitSheet) {
                if let error = presenter.currentError {
                    InitializationErrorView(
                        error: error,
                        onRetry: {
                            let action = presenter.retryAction
                            presenter.clearError()
                            action?()
                        },
                        onQuit: {
                            let action = presenter.quitAction
                            presenter.clearError()
                            action?()
                        }
                    )
                    .interactiveDismissDisabled() // Prevent dismissing with Esc or clicking outside
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Attach error presentation capability to a view
    func errorPresenter(_ presenter: ErrorPresenter) -> some View {
        modifier(ErrorPresenterModifier(presenter: presenter))
    }
}

