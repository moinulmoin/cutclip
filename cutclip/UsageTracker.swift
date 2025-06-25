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
    private let cacheManager = CacheManager()

    // MARK: - API Configuration
    private var baseURL: String { APIConfiguration.baseURL }
    private let maxFreeCredits = 3

    private init() {}

    // MARK: - Users API Methods

    /// GET /api/users/check-device (with smart caching)
    func checkDeviceStatus(forceRefresh: Bool = false) async throws -> UsageDeviceStatusResponse {
        // Check if we can use cached data
        if !forceRefresh {
            let cacheValidity = await getCacheValidity()
            if let cachedResult = await cacheManager.getCachedData(maxAge: cacheValidity) {
                print("📱 Using cached device status (age: \(Int(cachedResult.age/60)) minutes)")
                return .found(cachedResult.data)
            }
        }

        print("📱 Fetching fresh device status from API")
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        guard let encodedDeviceId = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw UsageError.invalidURL
        }
        let urlString = "\(baseURL)\(APIConfiguration.Endpoints.checkDevice)?deviceId=\(encodedDeviceId)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        isLoading = true
        defer { isLoading = false }

        // Retry logic with exponential backoff
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let request = APIConfiguration.createRequest(url: url)
                let (data, response) = try await APIConfiguration.performSecureRequest(request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw UsageError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(DeviceCheckResponse.self, from: data)

                    if let deviceData = result.data {
                        await MainActor.run {
                            self.currentCredits = deviceData.freeCredits
                            self.hasExceededLimit = deviceData.freeCredits <= 0 && !self.hasValidLicense(deviceData.user?.license)
                            self.hasInitializedCredits = true
                        }

                        // Cache the successful response (thread-safe)
                        await cacheManager.setCachedData(deviceData)
                        if attempt > 1 {
                            print("✅ Check device status succeeded on attempt \(attempt)")
                        }
                        return .found(deviceData)
                    } else {
                        return .notFound
                    }
                } else {
                    throw UsageError.serverError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                print("⚠️ Check device status failed on attempt \(attempt)/3: \(error.localizedDescription)")

                // Invalidate cache on network errors to prevent stale data
                if attempt == 3 && error is URLError {
                    await cacheManager.invalidate()
                    print("🗑️ Cache invalidated due to network errors")
                }

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        print("❌ Check device status failed after 3 attempts")
        throw lastError ?? UsageError.serverError(500)
    }

    /// POST /api/users/create-device (Create device only - no user until license)
    func createDeviceOnly() async throws -> CreateDeviceResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        let urlString = "\(baseURL)\(APIConfiguration.Endpoints.createDevice)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        var request = APIConfiguration.createRequest(url: url, method: "POST")

        let body = CreateDeviceRequest(
            deviceId: deviceId,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: "Mac"
        )
        request.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        // Retry logic with exponential backoff
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, response) = try await APIConfiguration.performSecureRequest(request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw UsageError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(CreateDeviceResponse.self, from: data)
                    currentCredits = maxFreeCredits // New devices get 3 free credits
                    hasInitializedCredits = true

                    // Invalidate cache after creating new device
                    await invalidateCache()
                    print("🗑️ Cache invalidated after creating new device")
                    print("📱 Device created with \(maxFreeCredits) free credits")

                    if attempt > 1 {
                        print("✅ Create device succeeded on attempt \(attempt)")
                    }
                    return result
                } else {
                    throw UsageError.serverError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                print("⚠️ Create device failed on attempt \(attempt)/3: \(error.localizedDescription)")

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        print("❌ Create device failed after 3 attempts")
        throw lastError ?? UsageError.serverError(500)
    }

    /// PUT /api/users/update-device (Creates user when license is added)
    func updateDeviceLicense(_ license: String) async throws -> UpdateDeviceResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        let urlString = "\(baseURL)\(APIConfiguration.Endpoints.updateDevice)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        var request = APIConfiguration.createRequest(url: url, method: "PUT")

        let body = UpdateDeviceRequest(deviceId: deviceId, license: license)
        request.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        // Retry logic with exponential backoff
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, response) = try await APIConfiguration.performSecureRequest(request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw UsageError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(UpdateDeviceResponse.self, from: data)
                    // Update local license storage
                    let licenseStored = SecureStorage.shared.storeLicense(license, deviceID: deviceId)
                    if licenseStored {
                        print("📄 License updated: \(result.message)")
                        print("👤 User created and linked to device")
                        print("🔐 License stored securely on device")
                    } else {
                        print("⚠️ Warning: License updated on server but failed to store locally")
                    }

                    if attempt > 1 {
                        print("✅ Update device license succeeded on attempt \(attempt)")
                    }
                    return result
                } else {
                    throw UsageError.serverError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                print("⚠️ Update device license failed on attempt \(attempt)/3: \(error.localizedDescription)")

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        print("❌ Update device license failed after 3 attempts")
        throw lastError ?? UsageError.serverError(500)
    }

    /// PUT /api/users/decrement-free-credits (Only used for devices without license)
    func decrementFreeCredits() async throws -> DecrementCreditsResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        let urlString = "\(baseURL)\(APIConfiguration.Endpoints.decrementCredits)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        var request = APIConfiguration.createRequest(url: url, method: "PUT")

        let body = DecrementCreditsRequest(deviceId: deviceId)
        request.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        // Retry logic with exponential backoff
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, response) = try await APIConfiguration.performSecureRequest(request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw UsageError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(DecrementCreditsResponse.self, from: data)
                    if let deviceData = result.data?.device {
                        await MainActor.run {
                            self.currentCredits = deviceData.freeCredits
                            self.hasExceededLimit = deviceData.freeCredits <= 0 && !SecureStorage.shared.hasValidLicense()
                            self.hasInitializedCredits = true
                        }

                        // Update cache with new credit count (thread-safe)
                        await self.cacheManager.updateCredits(deviceData.freeCredits)

                        print("📊 Free credits decremented: \(deviceData.freeCredits) remaining")
                    }
                    if attempt > 1 {
                        print("✅ Decrement credits succeeded on attempt \(attempt)")
                    }
                    return result
                } else if httpResponse.statusCode == 400 {
                    // Insufficient credits - don't retry this error
                    let result = try JSONDecoder().decode(DecrementCreditsResponse.self, from: data)
                    await MainActor.run {
                        self.hasExceededLimit = true
                    }
                    throw UsageError.insufficientCredits(result.message)
                } else {
                    throw UsageError.serverError(httpResponse.statusCode)
                }
            } catch let error as UsageError {
                // Don't retry business logic errors like insufficient credits
                if case .insufficientCredits = error {
                    throw error
                }
                lastError = error
                print("⚠️ Decrement credits failed on attempt \(attempt)/3: \(error.localizedDescription)")

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                lastError = error
                print("⚠️ Decrement credits failed on attempt \(attempt)/3: \(error.localizedDescription)")

                // Invalidate cache on final network error to force fresh fetch next time
                if attempt == 3 && error is URLError {
                    await cacheManager.invalidate()
                    print("🗑️ Cache invalidated due to decrement credits network error")
                }

                if attempt < 3 {
                    let delay = min(2.0 * Double(attempt), 5.0)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        print("❌ Decrement credits failed after 3 attempts")
        throw lastError ?? UsageError.serverError(500)
    }

    // MARK: - License Validation API

    /// POST /api/validate-license
    func validateLicense(licenseKey: String) async throws -> LicenseValidationResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        // 1. Call validation API
        let validationResult = try await callValidateLicenseAPI(licenseKey: licenseKey, deviceId: deviceId)

        if validationResult.valid {
            // 2. If valid, update device on backend to link license
            _ = try await updateDeviceLicense(licenseKey)

            // 3. Update local secure storage
            let stored = SecureStorage.shared.storeLicense(licenseKey, deviceID: deviceId)
            if !stored {
                print("⚠️ Failed to store license key locally after validation")
                // This is not a fatal error, as server holds the truth
            }

            // 4. Invalidate cache to force a fresh state
            await invalidateCache()
        }

        return validationResult
    }

    private func callValidateLicenseAPI(licenseKey: String, deviceId: String) async throws -> LicenseValidationResponse {
        guard let encodedLicense = licenseKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedDeviceId = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw UsageError.invalidURL
        }
        let urlString = "\(APIConfiguration.baseURL)\(APIConfiguration.Endpoints.validateLicense)?license=\(encodedLicense)&deviceId=\(encodedDeviceId)"

        return try await NetworkRetryHelper.retryOperation {
            guard let url = URL(string: urlString) else {
                throw UsageError.invalidURL
            }
            let request = APIConfiguration.createRequest(url: url)
            let (data, response) = try await APIConfiguration.performSecureRequest(request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // Try to parse error message for 4xx codes
                if let httpResponse = response as? HTTPURLResponse, 400...499 ~= httpResponse.statusCode {
                    if let errorResponse = try? JSONDecoder().decode(LicenseErrorResponse.self, from: data) {
                        throw UsageError.licenseValidationFailed(errorResponse.message)
                    }
                }
                throw UsageError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            return try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
        }
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

    // MARK: - Caching Logic

    private func getCacheValidity() async -> TimeInterval {
        let hasLicense = SecureStorage.shared.hasValidLicense()

        // Check if there was a recent cache invalidation (state change)
        let recentCacheInvalidation = await cacheManager.hasRecentInvalidation()
        if recentCacheInvalidation {
            return 0 // Force fresh data after state changes
        }

        // No cache during critical operations or for trial users close to limit
        if currentCredits <= 1 && !hasLicense {
            return 30 // 30 seconds for users about to expire
        }

        // Check if user just used credits (force fresh check)
        let recentCreditUsage = await cacheManager.hasRecentCreditUpdate()
        if recentCreditUsage {
            return 60 // 1 minute after credit usage
        }

        // Longer cache for licensed users, shorter for free users
        return hasLicense ? (10 * 60) : (3 * 60) // 10 minutes : 3 minutes
    }

    /// Force refresh cache (call when credits are used or license changes)
    func invalidateCache() async {
        await cacheManager.invalidate()
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

// MARK: - Thread-Safe Cache Manager

private actor CacheManager {
    private var lastFetchTime: Date?
    private var lastInvalidationTime: Date?
    private var lastCreditUpdateTime: Date?
    private var cachedData: DeviceData?
    private let defaultCacheValidity: TimeInterval = 10 * 60 // 10 minutes

    func getCachedData(maxAge: TimeInterval? = nil) -> (data: DeviceData, age: TimeInterval)? {
        guard let lastFetch = lastFetchTime,
              let data = cachedData else {
            return nil
        }

        let age = Date().timeIntervalSince(lastFetch)
        let maxValidAge = maxAge ?? defaultCacheValidity

        guard age < maxValidAge else {
            return nil
        }

        return (data: data, age: age)
    }

    func setCachedData(_ data: DeviceData) {
        self.cachedData = data
        self.lastFetchTime = Date()
    }

    func invalidate() {
        self.cachedData = nil
        self.lastFetchTime = nil
        self.lastInvalidationTime = Date()
        print("🗑️ Cache invalidated")
    }

    func hasRecentInvalidation() -> Bool {
        guard let invalidationTime = lastInvalidationTime else { return false }
        return Date().timeIntervalSince(invalidationTime) < 120 // 2 minutes
    }

    func updateCredits(_ newCredits: Int) {
        // Only update timestamp if credits actually changed
        if let currentData = cachedData, currentData.freeCredits != newCredits {
            self.lastCreditUpdateTime = Date()
            print("📊 Credits changed from \(currentData.freeCredits) to \(newCredits)")

            // Create a new DeviceData with updated credits
            let updatedData = DeviceData(
                id: currentData.id,
                deviceId: currentData.deviceId,
                freeCredits: newCredits,
                user: currentData.user
            )
            self.cachedData = updatedData
        }

        self.lastFetchTime = Date() // Reset cache time
    }

    func hasRecentCreditUpdate() -> Bool {
        guard let updateTime = lastCreditUpdateTime else { return false }
        return Date().timeIntervalSince(updateTime) < 120 // 2 minutes
    }
}

// MARK: - API Models

struct DeviceCheckResponse: Codable {
    let success: Bool
    let message: String
    let data: DeviceData?
}

struct DeviceData: Codable {
    let id: String
    let deviceId: String
    let freeCredits: Int
    let user: UserData?
}

struct UserData: Codable {
    let id: String
    let email: String?
    let name: String?
    let license: String?
}

struct CreateDeviceRequest: Codable {
    let deviceId: String
    let osVersion: String?
    let model: String?
}

struct CreateDeviceResponse: Codable {
    let success: Bool
    let message: String
    let data: CreatedDeviceData
}

struct CreatedDeviceData: Codable {
    let id: String
    let deviceId: String
    let osVersion: String?
    let model: String?
    let createdAt: String
}

struct UpdateDeviceRequest: Codable {
    let deviceId: String
    let license: String
}

struct UpdateDeviceResponse: Codable {
    let success: Bool
    let message: String
    let data: UpdateDeviceData?
}

struct UpdateDeviceData: Codable {
    let device: UpdatedDevice
}

struct UpdatedDevice: Codable {
    let deviceId: String
    let user: UpdatedUser
}

struct UpdatedUser: Codable {
    let id: String
    let license: String
}

struct DecrementCreditsRequest: Codable {
    let deviceId: String
}

struct DecrementCreditsResponse: Codable {
    let success: Bool
    let message: String
    let data: DecrementCreditsData?
}

struct DecrementCreditsData: Codable {
    let device: DecrementedDevice?
    let freeCredits: Int?
}

struct DecrementedDevice: Codable {
    let id: String
    let deviceId: String
    let freeCredits: Int
}

struct LicenseValidationResponse: Codable {
    let success: Bool
    let message: String
    var valid: Bool { success }
}

struct LicenseErrorResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Device Status Response

enum UsageDeviceStatusResponse {
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

enum UsageError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case insufficientCredits(String)
    case licenseValidationFailed(String)
    case networkError

    var errorDescription: String? {
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