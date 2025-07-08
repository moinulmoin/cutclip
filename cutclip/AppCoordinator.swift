//
//  AppCoordinator.swift
//  cutclip
//
//  Created by Moinul Moin on 7/2/25.
//

import Foundation
import SwiftUI
import Combine

/// Central coordinator for app-wide state management
@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var currentView: AppView = .disclaimer
    @Published private(set) var isInitializing = false
    @Published private(set) var initializationError: String?
    
    // MARK: - Dependencies
    let binaryManager: BinaryManager
    let errorHandler: ErrorHandler
    let licenseManager: LicenseManager
    let usageTracker: UsageTracker
    let networkMonitor: NetworkMonitor
    let cacheService: VideoCacheService
    
    // MARK: - Storage
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    
    // MARK: - App Views
    enum AppView: String, CaseIterable {
        case disclaimer
        case autoSetup
        case loading
        case licenseSetup
        case main
    }
    
    // MARK: - Initialization
    init(
        binaryManager: BinaryManager? = nil,
        errorHandler: ErrorHandler? = nil,
        licenseManager: LicenseManager? = nil,
        usageTracker: UsageTracker? = nil,
        networkMonitor: NetworkMonitor? = nil,
        cacheService: VideoCacheService? = nil
    ) {
        // Use provided instances or create new ones
        self.binaryManager = binaryManager ?? BinaryManager()
        self.errorHandler = errorHandler ?? ErrorHandler()
        self.licenseManager = licenseManager ?? LicenseManager.shared
        self.usageTracker = usageTracker ?? UsageTracker.shared
        self.networkMonitor = networkMonitor ?? NetworkMonitor.shared
        self.cacheService = cacheService ?? VideoCacheService()
        
        // Set up error handler connection
        self.licenseManager.errorHandler = self.errorHandler
        
        // Set up observers
        setupObservers()
        
        // Check binaries before initial state update
        self.binaryManager.checkBinaries()
        
        // Clean expired cache on startup
        Task {
            await self.cacheService.cleanExpiredCache()
        }
        
        // Initial state update
        updateAppState()
    }
    
    // MARK: - State Management
    
    /// Update the current app state based on various conditions
    func updateAppState() {
        print("🔄 AppCoordinator.updateAppState called")
        print("  - disclaimerAccepted: \(disclaimerAccepted)")
        print("  - binaryManager.isConfigured: \(binaryManager.isConfigured)")
        print("  - licenseManager.isInitialized: \(licenseManager.isInitialized)")
        print("  - licenseManager.needsLicenseSetup: \(licenseManager.needsLicenseSetup)")
        
        if !disclaimerAccepted {
            setView(.disclaimer)
        } else if !binaryManager.isConfigured {
            setView(.autoSetup)
        } else if !licenseManager.isInitialized {
            setView(.loading)
            // Initialize license manager if needed
            if !isInitializing {
                Task {
                    await initializeLicenseManager()
                }
            }
        } else if licenseManager.hasNetworkError || errorHandler.showingInitSheet {
            // Stay in loading state when there's a network error or showing init error
            // The error dialog will be shown as a sheet
            setView(.loading)
        } else if licenseManager.needsLicenseSetup && !licenseManager.hasNetworkError {
            // Only show license setup if it's not due to a network error
            setView(.licenseSetup)
        } else {
            // Show main view only when everything is properly initialized
            setView(.main)
        }
    }
    
    /// Transition to a new view with animation
    private func setView(_ view: AppView) {
        withAnimation(CleanDS.Animation.smooth) {
            currentView = view
        }
    }
    
    /// Initialize the license manager
    private func initializeLicenseManager() async {
        isInitializing = true
        initializationError = nil
        
        // License manager initialization happens automatically
        // We just need to wait for it to complete
        
        // Add a small delay to ensure smooth transition
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        isInitializing = false
        updateAppState()
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Observe disclaimer acceptance
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAppState()
            }
            .store(in: &cancellables)
        
        // Observe binary manager configuration changes
        binaryManager.$isConfigured
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("📡 BinaryManager.isConfigured changed, updating app state")
                self?.updateAppState()
            }
            .store(in: &cancellables)
        
        // Observe license manager changes
        licenseManager.$isInitialized
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAppState()
            }
            .store(in: &cancellables)
        
        licenseManager.$needsLicenseSetup
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAppState()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Methods
    
    /// Accept the disclaimer and proceed
    func acceptDisclaimer() {
        disclaimerAccepted = true
        updateAppState()
    }
    
    /// Complete auto setup successfully
    func completeAutoSetup() {
        // BinaryManager will update its own state
        // We just need to trigger state update
        updateAppState()
    }
    
    /// Complete license setup (either with license or free credits)
    func completeLicenseSetup() {
        updateAppState()
    }
    
    /// Reset app to initial state (for testing/debugging)
    func resetApp() {
        disclaimerAccepted = false
        updateAppState()
    }
    
    // MARK: - Computed Properties
    
    /// Check if the app is ready for use
    var isAppReady: Bool {
        disclaimerAccepted && 
        binaryManager.isConfigured && 
        licenseManager.isInitialized &&
        !licenseManager.needsLicenseSetup
    }
    
    /// Get a user-friendly message for the current state
    var stateMessage: String {
        switch currentView {
        case .disclaimer:
            return "Please accept the disclaimer to continue"
        case .autoSetup:
            return "Setting up required tools..."
        case .loading:
            return "Initializing..."
        case .licenseSetup:
            return "License setup required"
        case .main:
            if !networkMonitor.isConnected {
                return "No internet connection"
            }
            return "Ready to clip videos"
        }
    }
}

// MARK: - Environment Key

private struct AppCoordinatorKey: EnvironmentKey {
    nonisolated static let defaultValue: AppCoordinator? = nil
}

extension EnvironmentValues {
    var appCoordinator: AppCoordinator? {
        get { self[AppCoordinatorKey.self] }
        set { self[AppCoordinatorKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    func environmentAppCoordinator(_ coordinator: AppCoordinator) -> some View {
        self
            .environmentObject(coordinator)
            .environmentObject(coordinator.binaryManager)
            .environmentObject(coordinator.errorHandler)
            .environmentObject(coordinator.licenseManager)
            .environmentObject(coordinator.usageTracker)
            .environmentObject(coordinator.cacheService)
            .environment(\.appCoordinator, coordinator)
    }
}