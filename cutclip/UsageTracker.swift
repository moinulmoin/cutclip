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

    // MARK: - API Configuration
    private let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "http://localhost:3000/api"
    private let usersEndpoint = "/users"
    private let maxFreeCredits = 3

    private init() {}

    // MARK: - Users API Methods

    /// GET /api/users/check-device
    func checkDeviceStatus() async throws -> UsageDeviceStatusResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        let urlString = "\(baseURL)\(usersEndpoint)/check-device?deviceId=\(deviceId)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        isLoading = true
        defer { isLoading = false }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(DeviceCheckResponse.self, from: data)

            if let deviceData = result.data {
                currentCredits = deviceData.freeCredits
                hasExceededLimit = deviceData.freeCredits <= 0 && !hasValidLicense(deviceData.user?.license)
                return .found(deviceData)
            } else {
                return .notFound
            }
        } else {
            throw UsageError.serverError(httpResponse.statusCode)
        }
    }

    /// POST /api/users/create-device (Create device only - no user until license)
    func createDeviceOnly() async throws -> CreateDeviceResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        let urlString = "\(baseURL)\(usersEndpoint)/create-device"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateDeviceRequest(
            deviceId: deviceId,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: "Mac"
        )
        request.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(CreateDeviceResponse.self, from: data)
            currentCredits = maxFreeCredits // New devices get 3 free credits
            print("📱 Device created with \(maxFreeCredits) free credits")
            return result
        } else {
            throw UsageError.serverError(httpResponse.statusCode)
        }
    }

    /// PUT /api/users/update-device (Creates user when license is added)
    func updateDeviceLicense(_ license: String) async throws -> UpdateDeviceResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        let urlString = "\(baseURL)\(usersEndpoint)/update-device"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = UpdateDeviceRequest(deviceId: deviceId, license: license)
        request.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        let (data, response) = try await URLSession.shared.data(for: request)

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
            return result
        } else {
            throw UsageError.serverError(httpResponse.statusCode)
        }
    }

    /// PUT /api/users/decrement-free-credits (Only used for devices without license)
    func decrementFreeCredits() async throws -> DecrementCreditsResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()

        let urlString = "\(baseURL)\(usersEndpoint)/decrement-free-credits"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = DecrementCreditsRequest(deviceId: deviceId)
        request.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(DecrementCreditsResponse.self, from: data)
            if let deviceData = result.data?.device {
                currentCredits = deviceData.freeCredits
                hasExceededLimit = deviceData.freeCredits <= 0 && !SecureStorage.shared.hasValidLicense()
                print("📊 Free credits decremented: \(deviceData.freeCredits) remaining")
            }
            return result
        } else if httpResponse.statusCode == 400 {
            // Insufficient credits
            let result = try JSONDecoder().decode(DecrementCreditsResponse.self, from: data)
            hasExceededLimit = true
            throw UsageError.insufficientCredits(result.message)
        } else {
            throw UsageError.serverError(httpResponse.statusCode)
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

        // If still loading/initializing, show max credits to avoid "trial expired" during setup
        if isLoading && currentCredits == 0 {
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

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .insufficientCredits(let message):
            return "Insufficient credits: \(message)"
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