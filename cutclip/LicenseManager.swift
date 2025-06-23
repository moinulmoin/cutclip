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

    // Services
    private let deviceIdentifier = DeviceIdentifier.shared
    private let secureStorage = SecureStorage.shared
    private let usageTracker = UsageTracker.shared
    private let deviceRegistration = DeviceRegistrationService.shared

    private init() {
        initializeLicenseSystem()
    }

    // MARK: - Initialization

    func initializeLicenseSystem() {
        isLoading = true

        Task {
            await performInitialSetup()
            isLoading = false
        }
    }

    private func performInitialSetup() async {
        print("🔐 Initializing license system...")

        // 1. Check if device is already registered
        if !secureStorage.hasDeviceRegistration() {
            print("📱 Device not registered, registering now...")
            await registerDevice()
        }

        // 2. Check license status
        await refreshLicenseStatus()

        // 3. Determine if license setup is needed
        needsLicenseSetup = determineLicenseSetupRequired()

        print("🔐 License system initialized. Status: \(licenseStatus)")
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
            return true

        case .failure(let error):
            errorMessage = error
            return false
        }
    }

    func activateLicense(_ licenseKey: String) async -> Bool {
        print("🔑 Activating license: \(licenseKey.prefix(8))...")
        return await validateLicense(licenseKey)
    }

    func deactivateLicense() {
        print("🔓 Deactivating license...")

        _ = secureStorage.deleteLicense()
        licenseStatus = .unlicensed
        // License status will be refreshed automatically on next check
        needsLicenseSetup = true

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

                // Check for stored license
        if let storedLicense = secureStorage.retrieveLicense() {
            // Validate stored license with server
            let validationResult = await deviceRegistration.validateLicense(storedLicense.key)

            switch validationResult {
            case .success(_):
                licenseStatus = .licensed(
                    key: storedLicense.key,
                    expiresAt: nil, // No expiration from API
                    userEmail: nil  // No user email from API
                )
                return
            case .failure(_):
                // License is invalid, remove it
                let _ = secureStorage.deleteLicense()
                print("🔐 Stored license was invalid and removed")
                // Continue to check device status without license
            }
        }

        // Check device status with backend
        let deviceStatus = await deviceRegistration.checkDeviceStatus()

        switch deviceStatus {
        case .success(let response):
            if response.requiresLicense {
                licenseStatus = .trialExpired
            } else {
                licenseStatus = .freeTrial(remaining: response.remainingUses)
            }

        case .failure:
            // Fallback to local status if network fails
            let localStatus = usageTracker.getUsageStatus()
            switch localStatus {
            case .licensed:
                licenseStatus = .licensed(key: "cached", expiresAt: nil, userEmail: nil)
            case .freeTrial:
                licenseStatus = .freeTrial(remaining: usageTracker.getRemainingCredits())
            case .trialExpired:
                licenseStatus = .trialExpired
            }
        }
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
        switch licenseStatus {
        case .licensed:
            return false
        case .freeTrial(let remaining):
            return remaining == 0
        case .trialExpired, .unlicensed:
            return true
        case .unknown:
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
