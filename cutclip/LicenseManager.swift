//
//  LicenseManager.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation
import SwiftUI

@MainActor
class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // Published properties for UI binding
    @Published var licenseStatus: LicenseStatus = .unknown
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var needsLicenseSetup = false
    @Published var isInitialized = false
    @Published var hasNetworkError = false

    // Services
    private let deviceIdentifier = DeviceIdentifier.shared
    private let secureStorage = SecureStorage.shared
    private let usageTracker = UsageTracker.shared
    private let networkMonitor = NetworkMonitor.shared
    weak var errorHandler: ErrorHandler? {
        didSet {
            licenseErrorHandler.errorHandler = errorHandler
        }
    }
    
    // Error handling service
    private let licenseErrorHandler: LicenseErrorHandler
    
    // State management service
    private let licenseStateManager: LicenseStateManager
    
    // Analytics service
    private let licenseAnalyticsService: LicenseAnalyticsService

    // Task management
    private var initializationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    private init() {
        // No automatic initialization - prevents race condition
        // Initialization will be handled by cutclipApp.onAppear
        
        // Initialize error handler
        self.licenseErrorHandler = LicenseErrorHandler(
            networkMonitor: networkMonitor,
            errorHandler: nil // Will be set later when errorHandler is assigned
        )
        
        // Initialize state manager
        self.licenseStateManager = LicenseStateManager(
            secureStorage: secureStorage,
            usageTracker: usageTracker
        )
        
        // Initialize analytics service
        self.licenseAnalyticsService = LicenseAnalyticsService(
            deviceIdentifier: deviceIdentifier,
            secureStorage: secureStorage,
            usageTracker: usageTracker
        )
        
        // Set up error handler callbacks
        licenseErrorHandler.onNetworkError = { [weak self] hasError in
            self?.hasNetworkError = hasError
        }
        
        licenseErrorHandler.onErrorMessage = { [weak self] message in
            self?.errorMessage = message
        }
        
        licenseErrorHandler.onRetryAction = { [weak self] in
            self?.retryInitialization()
        }
        
        // Set up state manager callbacks
        licenseStateManager.onLicenseStatusChange = { [weak self] status in
            self?.licenseStatus = status
        }
        
        licenseStateManager.onNeedsSetupChange = { [weak self] needsSetup in
            self?.needsLicenseSetup = needsSetup
        }
    }

    // MARK: - Initialization

    func initializeLicenseSystem() {
        // Prevent multiple concurrent initializations
        guard !isLoading && !isInitialized else { return }

        // Cancel any existing initialization task
        initializationTask?.cancel()

        isLoading = true
        hasNetworkError = false

        initializationTask = Task {
            await performInitialSetup()
            await MainActor.run {
                self.isLoading = false
                self.isInitialized = true
                self.initializationTask = nil
            }
        }
    }
    
    func retryInitialization() {
        // Reset state
        isInitialized = false
        hasNetworkError = false
        errorMessage = nil
        
        // Retry initialization
        initializeLicenseSystem()
    }

    private func performInitialSetup() async {
        print("🔐 Initializing license system...")
        
        // Skip keychain operations on initial setup to avoid password prompt
        // User can use "Restore License" button if they have an existing license

        do {
            // 1. Initialize usage tracking and register device if needed
            _ = try await usageTracker.initializeApp()
            await usageTracker.registerDeviceIfNeeded()
            print("✅ Usage tracking initialized and device registered.")

            // 2. Don't check for stored license on fresh install
            // Just check device status for free credits
            await checkDeviceStatusOnly()

            // 3. Determine if license setup is needed
            needsLicenseSetup = await licenseStateManager.determineLicenseSetupRequired(currentLicenseStatus: licenseStatus)

            print("🔐 License system initialized. Status: \(licenseStatus)")

        } catch {
            // Delegate error handling to licenseErrorHandler
            await licenseErrorHandler.handleInitializationError(error)
            
            // Set fallback state
            licenseStatus = .unknown
            
            // Determine if license setup is required based on error type
            needsLicenseSetup = licenseErrorHandler.shouldRequireLicenseSetup(hasNetworkError: hasNetworkError)
            
            if hasNetworkError {
                print("🚨 Network error during initialization - attempting to use cached data")
            }
        }
    }

    // MARK: - License Operations
    
    @MainActor
    private func checkDeviceStatusOnly() async {
        do {
            let deviceStatus = try await usageTracker.checkDeviceStatus(forceRefresh: true)
            
            // Update license status based on device status only (no keychain check)
            switch deviceStatus {
            case .found(let deviceData):
                if let user = deviceData.user, let license = user.license, !license.isEmpty {
                    // User has a license
                    licenseStatus = .licensed(key: license, expiresAt: nil, userEmail: user.email)
                } else if deviceData.freeCredits > 0 {
                    // Using free credits
                    licenseStatus = .freeTrial(remaining: deviceData.freeCredits)
                } else {
                    // No credits left
                    licenseStatus = .trialExpired
                }
            case .notFound:
                // Device not found, treat as unlicensed
                licenseStatus = .unlicensed
            }
        } catch {
            print("⚠️ Failed to check device status: \(error)")
            licenseStatus = .unknown
        }
    }
    
    @MainActor
    func restoreLicense() async throws -> Bool {
        // Don't set isLoading here - that's for the entire view
        errorMessage = nil
        
        // This method explicitly checks keychain for stored license
        guard let storedLicense = secureStorage.retrieveLicense() else {
            errorMessage = "No license found on this device"
            return false
        }
        
        // Validate the stored license
        let validationResult = try await usageTracker.validateLicense(licenseKey: storedLicense.key)
        
        if validationResult.valid {
            // Update license status
            licenseStatus = licenseStateManager.updateLicenseStatus(
                licenseKey: storedLicense.key,
                isValid: true
            )
            
            // Force fresh device status check
            _ = try await usageTracker.checkDeviceStatus(forceRefresh: true)
            
            // Sync state
            licenseStatus = await licenseStateManager.syncLicenseState()
            needsLicenseSetup = false
            
            return true
        } else {
            // License is invalid, remove it
            let _ = secureStorage.deleteLicense()
            await usageTracker.invalidateCache()
            errorMessage = "The stored license is no longer valid"
            return false
        }
    }

    func validateLicense(_ licenseKey: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let result = try await usageTracker.validateLicense(licenseKey: licenseKey)

            if result.valid {
                licenseStatus = licenseStateManager.updateLicenseStatus(licenseKey: licenseKey, isValid: true)
                needsLicenseSetup = false

                // Force state synchronization after license change
                licenseStatus = await licenseStateManager.syncLicenseState()
                return true
            } else {
                errorMessage = result.message
                return false
            }
        } catch {
            errorMessage = licenseErrorHandler.handleLicenseValidationError(error)
            return false
        }
    }

    func activateLicense(_ licenseKey: String) async -> Bool {
        print("🔑 Activating license...")
        return await validateLicense(licenseKey)
    }

    func deactivateLicense() async {
        print("🔓 Deactivating license...")

        _ = secureStorage.deleteLicense()
        licenseStatus = .unlicensed
        // License status will be refreshed automatically on next check
        needsLicenseSetup = true

        // CRITICAL: Invalidate cache after license deactivation
        await usageTracker.invalidateCache()
        print("🗑️ Cache invalidated after license deactivation")

        // Force state synchronization after license change
        licenseStatus = await licenseStateManager.syncLicenseState()

        print("✅ License deactivated")
    }

    // MARK: - Usage Management

    func canUseApp() -> Bool {
        switch licenseStatus {
        case .licensed:
            return true
        case .freeTrial(let remaining):
            return remaining > 0
        case .trialExpired, .unlicensed, .unknown:
            return false
        }
    }

    func recordAppUsage() {
        guard canUseApp() else {
            print("❌ Cannot record usage - app usage not allowed")
            return
        }

        // Usage will be decremented through UsageTracker.decrementCredits()
        Task {
            do {
                try await usageTracker.decrementCredits()
                // Refresh status after usage
                await refreshLicenseStatus()
            } catch {
                print("❌ Failed to record usage: \(error)")
            }
        }
    }

    func getRemainingUses() -> Int {
        return usageTracker.getRemainingCredits()
    }

    // MARK: - Status Management

    func refreshLicenseStatus() async {
        print("🔄 Refreshing license status...")

        // Ensure cache is fresh after any license changes
        await usageTracker.invalidateCache()

        // Check for stored license first
        if let storedLicense = secureStorage.retrieveLicense() {
            // Validate stored license with server
            do {
                let validationResult = try await usageTracker.validateLicense(licenseKey: storedLicense.key)

                if validationResult.valid {
                    // Update license status
                    licenseStatus = licenseStateManager.updateLicenseStatus(
                        licenseKey: storedLicense.key,
                        isValid: true
                    )
                    // Force fresh device status check to sync credit counts
                    do {
                        _ = try await usageTracker.checkDeviceStatus(forceRefresh: true)
                        // Sync state after successful validation
                        licenseStatus = await licenseStateManager.syncLicenseState()
                    } catch {
                        print("⚠️ Failed to sync device status after license validation: \(error)")
                    }
                    return
                } else {
                    // License is invalid, remove it and invalidate all state
                    let _ = secureStorage.deleteLicense()
                    await usageTracker.invalidateCache()
                    print("🔐 Stored license was invalid and removed")
                    // Continue to check device status without license
                }
            } catch {
                // License is invalid due to an error, remove it and invalidate all state
                print("🔐 Stored license was invalid and removed due to error: \(error.localizedDescription)")
                let _ = secureStorage.deleteLicense()
                await usageTracker.invalidateCache()
                // Continue to check device status without license
            }
        }

        // Get fresh device status for license-less state
        do {
            _ = try await usageTracker.checkDeviceStatus(forceRefresh: true)
            // Sync state after device status check
            licenseStatus = await licenseStateManager.syncLicenseState()
        } catch {
            print("❌ Failed to refresh device status during license refresh: \(error)")
            // Fall back to local state
            licenseStatus = .unknown
        }

        print("🔄 State synchronized: \(licenseStatus.debugDescription)")
    }


    // MARK: - Debug & Testing

    func getDebugInfo() -> [String: Any] {
        return licenseAnalyticsService.getDebugInfo(
            licenseStatus: licenseStatus,
            needsLicenseSetup: needsLicenseSetup
        )
    }

    func resetForTesting() {
        licenseAnalyticsService.resetForTesting()
        licenseStateManager.resetLicenseStatus()
        errorMessage = nil

        // Re-initialize
        initializeLicenseSystem()
    }
    
    func getLicenseAnalytics() -> [String: Any] {
        return licenseAnalyticsService.getLicenseAnalytics(licenseStatus: licenseStatus)
    }


}
