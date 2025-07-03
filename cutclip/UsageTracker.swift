//
//  UsageTracker.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

@MainActor
class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published var currentCredits: Int = 0
    @Published var hasExceededLimit: Bool = false
    @Published var isLoading: Bool = false
    @Published var hasInitializedCredits: Bool = false

    // Thread-safe cache manager
    private let cacheService = CacheService()
    
    // API client with retry logic
    private let apiClient = APIClient()
    
    // Device repository for device operations
    private let deviceRepository: DeviceRepository
    
    // License repository for license operations
    private let licenseRepository: LicenseRepository

    // MARK: - API Configuration
    private var baseURL: String { APIConfiguration.baseURL }
    private let maxFreeCredits = 3
    
    // MARK: - Initialization
    private init() {
        self.deviceRepository = DeviceRepository(cacheService: cacheService)
        self.licenseRepository = LicenseRepository(deviceRepository: deviceRepository, cacheService: cacheService)
        
        // Set up callbacks for state updates
        deviceRepository.onCreditsUpdate = { [weak self] credits, hasExceeded in
            Task { @MainActor in
                self?.currentCredits = credits
                self?.hasExceededLimit = hasExceeded
                self?.hasInitializedCredits = true
            }
        }
        
        deviceRepository.onLoadingStateChange = { [weak self] isLoading in
            Task { @MainActor in
                self?.isLoading = isLoading
            }
        }
    }

    // MARK: - Users API Methods

    /// GET /api/users/check-device (with smart caching)
    func checkDeviceStatus(forceRefresh: Bool = false) async throws -> UsageDeviceStatusResponse {
        return try await deviceRepository.checkDeviceStatus(forceRefresh: forceRefresh)
    }

    /// POST /api/users/create-device (Create device only - no user until license)
    func createDeviceOnly() async throws -> CreateDeviceResponse {
        return try await deviceRepository.createDeviceOnly()
    }

    /// PUT /api/users/update-device (Creates user when license is added)
    func updateDeviceLicense(_ license: String) async throws -> UpdateDeviceResponse {
        return try await deviceRepository.updateDeviceLicense(license)
    }

    /// PUT /api/users/decrement-free-credits (Only used for devices without license)
    func decrementFreeCredits() async throws -> DecrementCreditsResponse {
        return try await deviceRepository.decrementFreeCredits()
    }

    // MARK: - License Validation API

    /// POST /api/validate-license
    func validateLicense(licenseKey: String) async throws -> LicenseValidationResponse {
        return try await licenseRepository.validateLicense(licenseKey: licenseKey)
    }


    // MARK: - Main App Flow

    /// Initialize app - check device status or create device
    func initializeApp() async throws -> UsageDeviceStatusResponse {
        let status = try await checkDeviceStatus()

        switch status {
        case .found(let deviceData):
            print("📱 Device found with \(deviceData.freeCredits) credits")
            if deviceData.user != nil {
                print("👤 Device has licensed user")
            } else {
                print("🆓 Device using free credits (no user yet)")
            }
            return status

        case .notFound:
            print("📱 Device not found, creating new device...")
            _ = try await createDeviceOnly()
            let deviceId = DeviceIdentifier.shared.getDeviceID()
            return .found(DeviceData(
                id: "new",
                deviceId: deviceId,
                freeCredits: maxFreeCredits,
                user: nil
            ))
        }
    }

    // MARK: - Convenience Methods

    /// Main method to decrement credits when user clips a video
    func decrementCredits() async throws {
        // Only decrement credits if user has no valid license
        if SecureStorage.shared.hasValidLicense() {
            print("📄 User has valid license - unlimited usage, no credits decremented")
            return
        }

        // User has no license, decrement free credits on device
        print("🆓 No license found, decrementing free credits...")
        _ = try await decrementFreeCredits()
    }

    /// Update license (creates user and links to device)
    func updateLicense(_ license: String) async throws {
        print("📄 Adding license to device (will create user)...")
        _ = try await updateDeviceLicense(license)

        // CRITICAL: Invalidate cache after updating license
        await invalidateCache()
        print("🗑️ Cache invalidated after updating device license")
    }

    /// This function handles the one-time registration data storage for analytics.
    /// It should be called once during the app's initial setup.
    func registerDeviceIfNeeded() async {
        if SecureStorage.shared.hasDeviceRegistration() {
            return
        }

        print("📝 Performing one-time device registration for analytics...")
        do {
            let status = try await initializeApp()
            if case .found(let deviceData) = status {
                let registrationData: [String: Any] = [
                    "device_id": deviceData.deviceId,
                    "registered_at": ISO8601DateFormatter().string(from: Date()),
                    "initial_free_credits": deviceData.freeCredits,
                    "has_initial_license": deviceData.user?.license != nil
                ]
                if !SecureStorage.shared.storeDeviceRegistration(registrationData) {
                    print("⚠️ Failed to store one-time device registration data.")
                } else {
                    print("✅ One-time device registration data stored.")
                }
            }
        } catch {
            print("❌ Failed to perform one-time device registration: \(error.localizedDescription)")
        }
    }

    // MARK: - Usage Logic

    func canUseApp() -> Bool {
        // Check if user has valid license first
        if SecureStorage.shared.hasValidLicense() {
            return true // Unlimited usage with license
        }

        // Check free credits only if no license
        return currentCredits > 0
    }

    func getRemainingCredits() -> Int {
        if SecureStorage.shared.hasValidLicense() {
            return -1 // Unlimited
        }
        return max(0, currentCredits)
    }

    func getUsageStatus() -> UsageStatus {
        if SecureStorage.shared.hasValidLicense() {
            return .licensed
        }

        // If we haven't initialized credits yet, assume user has credits to avoid blocking
        if !hasInitializedCredits {
            return .freeTrial(remaining: maxFreeCredits)
        }

        if currentCredits > 0 {
            return .freeTrial(remaining: currentCredits)
        } else {
            return .trialExpired
        }
    }

    // MARK: - Helper Methods

    private func hasValidLicense(_ license: String?) -> Bool {
        guard let license = license, !license.isEmpty else { return false }
        return license.hasPrefix("PRO-") || license.hasPrefix("ENTERPRISE-")
    }


    /// Force refresh cache (call when credits are used or license changes)
    func invalidateCache() async {
        await cacheService.invalidate()
    }

    // MARK: - Analytics Data

    func getUsageAnalytics() -> [String: Any] {
        return [
            "current_credits": currentCredits,
            "max_free_credits": maxFreeCredits,
            "has_exceeded_limit": hasExceededLimit,
            "has_license": SecureStorage.shared.hasValidLicense(),
            "usage_status": getUsageStatus().rawValue
        ]
    }
}


// MARK: - API Models

public struct DeviceCheckResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let data: DeviceData?
}

public struct DeviceData: Codable, Sendable {
    let id: String
    let deviceId: String
    let freeCredits: Int
    let user: UserData?
}

public struct UserData: Codable, Sendable {
    let id: String
    let email: String?
    let name: String?
    let license: String?
}

public struct CreateDeviceRequest: Codable, Sendable {
    let deviceId: String
    let osVersion: String?
    let model: String?
}

public struct CreateDeviceResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let data: CreatedDeviceData
}

public struct CreatedDeviceData: Codable, Sendable {
    let id: String
    let deviceId: String
    let osVersion: String?
    let model: String?
    let createdAt: String
}

public struct UpdateDeviceRequest: Codable, Sendable {
    let deviceId: String
    let license: String
}

public struct UpdateDeviceResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let data: UpdateDeviceData?
}

public struct UpdateDeviceData: Codable, Sendable {
    let device: UpdatedDevice
}

public struct UpdatedDevice: Codable, Sendable {
    let deviceId: String
    let user: UpdatedUser
}

public struct UpdatedUser: Codable, Sendable {
    let id: String
    let license: String
}

public struct DecrementCreditsRequest: Codable, Sendable {
    let deviceId: String
}

public struct DecrementCreditsResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let data: DecrementCreditsData?
}

public struct DecrementCreditsData: Codable, Sendable {
    let device: DecrementedDevice?
    let freeCredits: Int?
}

public struct DecrementedDevice: Codable, Sendable {
    let id: String
    let deviceId: String
    let freeCredits: Int
}

public struct LicenseValidationResponse: Codable, Sendable {
    let success: Bool
    let message: String
    var valid: Bool { success }
}

public struct LicenseErrorResponse: Codable, Sendable {
    let success: Bool
    let message: String
}

// MARK: - Device Status Response

public enum UsageDeviceStatusResponse: Sendable {
    case found(DeviceData)
    case notFound
}

// MARK: - Usage Status Enum

enum UsageStatus: CaseIterable {
    case freeTrial(remaining: Int)
    case trialExpired
    case licensed

    var displayText: String {
        switch self {
        case .freeTrial(let remaining):
            return "Free Trial (\(remaining) credits left)"
        case .trialExpired:
            return "Trial Expired"
        case .licensed:
            return "Licensed"
        }
    }

    var canUseApp: Bool {
        switch self {
        case .freeTrial, .licensed:
            return true
        case .trialExpired:
            return false
        }
    }

    var rawValue: String {
        switch self {
        case .freeTrial:
            return "free_trial"
        case .trialExpired:
            return "trial_expired"
        case .licensed:
            return "licensed"
        }
    }

    // Required for CaseIterable
    static var allCases: [UsageStatus] {
        return [.freeTrial(remaining: 0), .trialExpired, .licensed]
    }
}

// MARK: - Usage Errors

public enum UsageError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case insufficientCredits(String)
    case licenseValidationFailed(String)
    case licenseError(String)
    case networkError

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Request failed. Please check your connection and retry."
        case .invalidResponse:
            return "Server temporarily unavailable. Please try again in a moment."
        case .serverError(let code):
            if code >= 500 {
                return "Server temporarily unavailable. Please try again in a moment."
            } else {
                return "Request failed. Please check your connection and retry."
            }
        case .decodingError:
            return "Server temporarily unavailable. Please try again in a moment."
        case .insufficientCredits(_):
            return "Free clips used up. Enter a license key for unlimited clipping."
        case .licenseValidationFailed(let message):
            return message
        case .licenseError(let message):
            return message
        case .networkError:
            return "No internet connection. CutClip requires internet."
        }
    }
}

// MARK: - Usage Status Extensions

extension UsageStatus {
    var remainingCount: Int? {
        switch self {
        case .freeTrial(let remaining):
            return remaining
        case .trialExpired:
            return 0
        case .licensed:
            return nil // Unlimited
        }
    }
}