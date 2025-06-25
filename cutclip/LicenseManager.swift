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

    // Services
    private let deviceIdentifier = DeviceIdentifier.shared
    private let secureStorage = SecureStorage.shared
    private let usageTracker = UsageTracker.shared
    private let deviceRegistration = DeviceRegistrationService.shared

    // Task management
    private var initializationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    private init() {
        // No automatic initialization - prevents race condition
        // Initialization will be handled by cutclipApp.onAppear
    }

    // MARK: - Initialization

    func initializeLicenseSystem() {
        // Prevent multiple concurrent initializations
        guard !isLoading && !isInitialized else { return }

        // Cancel any existing initialization task
        initializationTask?.cancel()

        isLoading = true

        initializationTask = Task {
            await performInitialSetup()
            await MainActor.run {
                self.isLoading = false
                self.isInitialized = true
                self.initializationTask = nil
            }
        }
    }

    private func performInitialSetup() async {
        print("🔐 Initializing license system...")

        do {
            // 1. Initialize usage tracking first
            let _ = try await usageTracker.initializeApp()
            print("✅ Usage tracking initialized")

            // 2. Check if device is already registered
            if !secureStorage.hasDeviceRegistration() {
                print("📱 Device not registered, registering now...")
                await registerDevice()
            }

            // 3. Check license status
            await refreshLicenseStatus()

            // 4. Determine if license setup is needed
            needsLicenseSetup = determineLicenseSetupRequired()

            print("🔐 License system initialized. Status: \(licenseStatus)")

        } catch {
            print("❌ Failed to initialize license system: \(error)")

            // Provide specific error messages based on error type
            if let usageError = error as? UsageError {
                switch usageError {
                case .networkError:
                    errorMessage = "No internet connection. Please check your connection and restart the app."
                case .serverError(let code) where code >= 500:
                    errorMessage = "Server temporarily unavailable. Please try again in a moment."
                case .serverError(_):
                    errorMessage = "Unable to connect to CutClip servers. Please check your connection."
                case .invalidResponse, .decodingError:
                    errorMessage = "Server communication error. Please try again later."
                default:
                    errorMessage = "Failed to initialize CutClip. Please restart the app."
                }
            } else if error is URLError {
                errorMessage = "No internet connection. Please check your connection and restart the app."
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "No internet connection. Please check your connection and restart the app."
            } else {
                errorMessage = "Failed to initialize CutClip. Please restart the app."
            }

            // Set fallback state to allow app to function with limited features
            licenseStatus = .unknown
            needsLicenseSetup = true

            // For critical network errors, don't allow app to proceed normally
            if error is URLError || (error as? UsageError)?.localizedDescription.contains("network") == true {
                print("🚨 Critical network error during initialization - app functionality will be limited")
            }
        }
    }

    // MARK: - License Operations

    func validateLicense(_ licenseKey: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let result = await deviceRegistration.validateLicense(licenseKey)

        switch result {
        case .success(_):
            licenseStatus = .licensed(
                key: licenseKey,
                expiresAt: nil, // No expiration from API
                userEmail: nil  // No user email from API
            )
            // License status will be refreshed automatically on next check
            needsLicenseSetup = false

            // CRITICAL: Invalidate cache after license activation
            await usageTracker.invalidateCache()
            print("🗑️ Cache invalidated after license activation")

            // Force state synchronization after license change
            await syncLicenseState()

            return true

        case .failure(let error):
            // Map generic errors to user-friendly license errors
            if error.contains("already used") {
                errorMessage = "License already in use on another device. Contact support if needed."
            } else if error.contains("invalid") || error.contains("not found") {
                errorMessage = "Invalid license key. Please check and try again."
            } else if error.contains("internet") || error.contains("connection") {
                errorMessage = "Unable to verify license. Check your internet connection."
            } else {
                errorMessage = "Unable to verify license. Check your internet connection."
            }
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
        await syncLicenseState()

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
            let validationResult = await deviceRegistration.validateLicense(storedLicense.key)

            switch validationResult {
            case .success(_):
                // Update license status
                licenseStatus = .licensed(
                    key: storedLicense.key,
                    expiresAt: nil,
                    userEmail: nil
                )
                // Force fresh device status check to sync credit counts
                do {
                    _ = try await usageTracker.checkDeviceStatus(forceRefresh: true)
                    // Sync state after successful validation
                    await syncLicenseState()
                } catch {
                    print("⚠️ Failed to sync device status after license validation: \(error)")
                }
                return
            case .failure(_):
                // License is invalid, remove it and invalidate all state
                let _ = secureStorage.deleteLicense()
                await usageTracker.invalidateCache()
                print("🔐 Stored license was invalid and removed")
                // Continue to check device status without license
            }
        }

        // Get fresh device status for license-less state
        do {
            _ = try await usageTracker.checkDeviceStatus(forceRefresh: true)
            // Sync state after device status check
            await syncLicenseState()
        } catch {
            print("❌ Failed to refresh device status during license refresh: \(error)")
            // Fall back to local state
            licenseStatus = .unknown
        }
    }

    /// Centralized state synchronization to ensure consistency
    private func syncLicenseState() async {
        let currentStatus = usageTracker.getUsageStatus()

        // Only update license status if we don't have a valid stored license
        guard secureStorage.retrieveLicense() == nil else {
            // If we have a stored license, ensure status reflects this
            if case .licensed = licenseStatus {
                // Already correct
                return
            } else {
                // Fix state mismatch
                if let storedLicense = secureStorage.retrieveLicense() {
                    licenseStatus = .licensed(key: storedLicense.key, expiresAt: nil, userEmail: nil)
                }
            }
            return
        }

        // Sync license status with usage tracker state
        switch currentStatus {
        case .licensed:
            // This shouldn't happen since we checked for stored license above
            // But handle it gracefully
            if let storedLicense = secureStorage.retrieveLicense() {
                licenseStatus = .licensed(key: storedLicense.key, expiresAt: nil, userEmail: nil)
            } else {
                licenseStatus = .unlicensed
            }
        case .freeTrial(let remaining):
            licenseStatus = .freeTrial(remaining: remaining)
        case .trialExpired:
            licenseStatus = .trialExpired
        }

        print("🔄 State synchronized: \(licenseStatus.debugDescription)")
    }

    private func registerDevice() async {
        let result = await deviceRegistration.registerDeviceAndCheckLicense()

        switch result {
        case .success(let response):
            print("✅ Device registered: \(response.message)")

        case .failure(let error):
            print("❌ Device registration failed: \(error)")
            errorMessage = error
        }
    }

    private func determineLicenseSetupRequired() -> Bool {
        // If user has a valid license, no setup needed
        if case .licensed = licenseStatus {
            return false
        }

        // Check if user has free credits available
        let usageStatus = usageTracker.getUsageStatus()
        switch usageStatus {
        case .licensed:
            return false
        case .freeTrial(let remaining):
            return remaining == 0  // Only require setup if no credits left
        case .trialExpired:
            return true
        }
    }

    // MARK: - Debug & Testing

    func getDebugInfo() -> [String: Any] {
        let deviceInfo = deviceIdentifier.getDeviceInfo()
        let usageAnalytics = usageTracker.getUsageAnalytics()

        return [
            "device_info": deviceInfo,
            "usage_analytics": usageAnalytics,
            "license_status": licenseStatus.debugDescription,
            "has_stored_license": secureStorage.hasValidLicense(),
            "has_device_registration": secureStorage.hasDeviceRegistration(),
            "needs_license_setup": needsLicenseSetup
        ]
    }

    func resetForTesting() {
        print("🧪 Resetting license system for testing...")

        _ = secureStorage.clearAllData()
        // Usage is managed by the API, not locally
        licenseStatus = .unknown
        needsLicenseSetup = false
        errorMessage = nil

        // Re-initialize
        initializeLicenseSystem()
    }


}

// MARK: - License Status Enum

enum LicenseStatus: Equatable {
    case unknown
    case unlicensed
    case freeTrial(remaining: Int)
    case trialExpired
    case licensed(key: String, expiresAt: Date?, userEmail: String?)

    var displayText: String {
        switch self {
        case .unknown:
            return "Checking license..."
        case .unlicensed:
            return "No license"
        case .freeTrial(let remaining):
            return "Free trial (\(remaining) uses left)"
        case .trialExpired:
            return "Trial expired"
        case .licensed(_, let expiresAt, _):
            if let expiry = expiresAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return "Licensed until \(formatter.string(from: expiry))"
            } else {
                return "Licensed"
            }
        }
    }

    var canUseApp: Bool {
        switch self {
        case .licensed:
            return true
        case .freeTrial(let remaining):
            return remaining > 0
        case .unknown, .unlicensed, .trialExpired:
            return false
        }
    }

    var requiresLicenseSetup: Bool {
        switch self {
        case .trialExpired, .unlicensed:
            return true
        case .freeTrial(let remaining):
            return remaining == 0
        case .licensed, .unknown:
            return false
        }
    }

    var debugDescription: String {
        switch self {
        case .unknown:
            return "unknown"
        case .unlicensed:
            return "unlicensed"
        case .freeTrial(let remaining):
            return "freeTrial(\(remaining))"
        case .trialExpired:
            return "trialExpired"
        case .licensed(let key, let expiresAt, let email):
            return "licensed(key: \(key.prefix(8))..., expires: \(expiresAt?.description ?? "never"), email: \(email ?? "none"))"
        }
    }
}
