//
//  DeviceRegistrationService.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

@MainActor
class DeviceRegistrationService: ObservableObject {
    static let shared = DeviceRegistrationService()

    @Published var isRegistering = false
    @Published var registrationError: String?

    private var baseURL: String {
        ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "http://localhost:3000/api"
    }

    private init() {}

    // MARK: - Main Device Registration Flow

    func registerDeviceAndCheckLicense() async -> DeviceRegistrationResult {
        isRegistering = true
        registrationError = nil

        defer {
            isRegistering = false
        }

        do {
            let deviceID = DeviceIdentifier.shared.getDeviceID()
            let deviceInfo = DeviceIdentifier.shared.getDeviceInfo()

            // Step 1: Check if user exists
            let userCheckResult = try await checkUserExists(deviceId: deviceID)

            let response: DeviceRegistrationResponse

            if userCheckResult.exists {
                // Step 2: User exists - check license status and quota
                print("✅ User exists, checking license status...")
                response = try await handleExistingUser(deviceId: deviceID, userInfo: userCheckResult)
            } else {
                // Step 3: New user - create user and start free trial
                print("✅ New user, creating account with free trial...")
                response = try await handleNewUser(deviceId: deviceID, deviceInfo: deviceInfo)
            }

            // Store registration data
            let registrationData: [String: Any] = [
                "device_id": response.deviceId,
                "registered_at": ISO8601DateFormatter().string(from: Date()),
                "remaining_uses": response.remainingUses,
                "requires_license": response.requiresLicense,
                "registration_token": response.registrationToken ?? "",
                "user_status": response.userStatus,
                "api_response": response.toDict()
            ]

            if SecureStorage.shared.storeDeviceRegistration(registrationData) {
                print("✅ Device registration completed successfully")
                return .success(response)
            } else {
                print("❌ Failed to store registration data")
                return .failure("Failed to store registration data")
            }

        } catch {
            let errorMessage = "Registration failed: \(error.localizedDescription)"
            registrationError = errorMessage
            print("❌ Device registration error: \(errorMessage)")
            return .failure(errorMessage)
        }
    }

    // MARK: - User Management

    private func checkUserExists(deviceId: String) async throws -> UserCheckResponse {
        let url = URL(string: "\(baseURL)/users/check-device?deviceId=\(deviceId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let success = json?["success"] as? Bool ?? false
        let deviceData = json?["data"] as? [String: Any]
        let userData = deviceData?["user"] as? [String: Any]

        return UserCheckResponse(
            exists: success && deviceData != nil,
            userId: userData?["id"] as? String,
            remainingUses: deviceData?["freeCredits"] as? Int ?? 0,
            totalUsage: 0, // Not provided in API response
            hasLicense: userData?["license"] != nil,
            licenseStatus: userData?["license"] != nil ? "active" : nil,
            quotaComplete: (deviceData?["freeCredits"] as? Int ?? 0) <= 0
        )
    }

    private func handleExistingUser(deviceId: String, userInfo: UserCheckResponse) async throws -> DeviceRegistrationResponse {
        // Check if user has license
        if userInfo.hasLicense && userInfo.licenseStatus == "active" {
            // User has valid license - allow usage
            return DeviceRegistrationResponse(
                deviceId: deviceId,
                registered: true,
                remainingUses: -1, // Unlimited for licensed users
                requiresLicense: false,
                registrationToken: nil,
                message: "License active - unlimited usage",
                userStatus: "licensed"
            )
        }

        // Check if quota is complete
        if userInfo.quotaComplete || userInfo.remainingUses <= 0 {
            // No license and quota exhausted - user needs license
            return DeviceRegistrationResponse(
                deviceId: deviceId,
                registered: true,
                remainingUses: 0,
                requiresLicense: true,
                registrationToken: nil,
                message: "Free trial expired. License required to continue using CutClip.",
                userStatus: "trial_expired"
            )
        }

        // User exists but still has free trial uses
        return DeviceRegistrationResponse(
            deviceId: deviceId,
            registered: true,
            remainingUses: userInfo.remainingUses,
            requiresLicense: false,
            registrationToken: nil,
            message: "Free trial - \(userInfo.remainingUses) uses remaining",
            userStatus: "trial_active"
        )
    }

    private func handleNewUser(deviceId: String, deviceInfo: [String: String]) async throws -> DeviceRegistrationResponse {
        let url = URL(string: "\(baseURL)/users/create-device")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "deviceId": deviceId,
            "osVersion": deviceInfo["os_version"] ?? "",
            "model": deviceInfo["device_model"] ?? ""
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let deviceData = json?["data"] as? [String: Any]

        return DeviceRegistrationResponse(
            deviceId: deviceData?["deviceId"] as? String ?? deviceId,
            registered: json?["success"] as? Bool ?? false,
            remainingUses: 100, // New devices get 100 free credits as per API docs
            requiresLicense: false,
            registrationToken: nil,
            message: json?["message"] as? String ?? "Device created successfully",
            userStatus: "trial_active"
        )
    }

        // MARK: - License Validation

    func validateLicense(_ licenseKey: String) async -> LicenseValidationResult {
        isRegistering = true
        registrationError = nil

        defer {
            isRegistering = false
        }

        do {
            let deviceID = DeviceIdentifier.shared.getDeviceID()
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

            let response = try await callValidateLicenseAPI(
                licenseKey: licenseKey,
                deviceId: deviceID,
                appVersion: appVersion
            )

            if response.valid {
                // Store license
                if SecureStorage.shared.storeLicense(licenseKey, deviceID: deviceID) {
                    print("✅ License validated and stored")
                    return .success(response)
                } else {
                    return .failure("Failed to store license")
                }
            } else {
                return .failure(response.errorMessage ?? "Invalid license")
            }

        } catch {
            let errorMessage = "License validation failed: \(error.localizedDescription)"
            registrationError = errorMessage
            return .failure(errorMessage)
        }
    }

    // MARK: - Usage Tracking

    func recordUsage() async -> UsageResult {
        do {
            let deviceID = DeviceIdentifier.shared.getDeviceID()
            let response = try await callRecordUsageAPI(deviceId: deviceID)
            return .success(response)
        } catch {
            return .failure("Failed to record usage: \(error.localizedDescription)")
        }
    }

    private func callRecordUsageAPI(deviceId: String) async throws -> UsageResponse {
        let url = URL(string: "\(baseURL)/users/decrement-free-credits")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "deviceId": deviceId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let dataDict = json?["data"] as? [String: Any]
        let deviceData = dataDict?["device"] as? [String: Any]

        return UsageResponse(
            remainingUses: deviceData?["freeCredits"] as? Int ?? 0,
            totalUsage: 0, // Not provided in this API response
            requiresLicense: (deviceData?["freeCredits"] as? Int ?? 0) <= 0,
            message: json?["message"] as? String ?? ""
        )
    }

        // MARK: - Device Status Check

    func checkDeviceStatus() async -> DeviceStatusResult {
        do {
            let deviceID = DeviceIdentifier.shared.getDeviceID()
            let response = try await callCheckDeviceStatusAPI(deviceId: deviceID)
            return .success(response)

        } catch {
            return .failure("Failed to check device status: \(error.localizedDescription)")
        }
    }

    // MARK: - Legacy Methods (for backward compatibility)

    func registerDevice() async -> DeviceRegistrationResult {
        return await registerDeviceAndCheckLicense()
    }
}

// MARK: - HTTP API Calls

extension DeviceRegistrationService {

    private func callValidateLicenseAPI(licenseKey: String, deviceId: String, appVersion: String) async throws -> LicenseValidationResponse {
        let url = URL(string: "\(baseURL)/users/update-device")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "deviceId": deviceId,
            "license": licenseKey
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let success = json?["success"] as? Bool ?? false
        let dataDict = json?["data"] as? [String: Any]
        let deviceData = dataDict?["device"] as? [String: Any]
        let userData = deviceData?["user"] as? [String: Any]

        return LicenseValidationResponse(
            valid: success && userData?["license"] != nil,
            expiresAt: nil, // Not provided in this API
            userEmail: userData?["email"] as? String,
            licenseType: "PRO", // Default license type
            errorMessage: success ? nil : (json?["message"] as? String)
        )
    }

    private func callCheckDeviceStatusAPI(deviceId: String) async throws -> DeviceStatusResponse {
        let url = URL(string: "\(baseURL)/users/check-device?deviceId=\(deviceId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let deviceData = json?["data"] as? [String: Any]
        let userData = deviceData?["user"] as? [String: Any]

        return DeviceStatusResponse(
            deviceId: deviceData?["deviceId"] as? String ?? deviceId,
            remainingUses: deviceData?["freeCredits"] as? Int ?? 0,
            totalUsage: 0, // Not provided in API response
            requiresLicense: userData?["license"] == nil && (deviceData?["freeCredits"] as? Int ?? 0) <= 0,
            lastUsedAt: Date(), // Not provided in API response
            status: json?["success"] as? Bool == true ? "active" : "unknown"
        )
    }
}

// MARK: - API Error Types

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case noData
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid API response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noData:
            return "No data received"
        case .invalidJSON:
            return "Invalid JSON response"
        }
    }
}

// MARK: - Data Models

struct UserCheckResponse {
    let exists: Bool
    let userId: String?
    let remainingUses: Int
    let totalUsage: Int
    let hasLicense: Bool
    let licenseStatus: String?
    let quotaComplete: Bool
}

struct DeviceRegistrationResponse {
    let deviceId: String
    let registered: Bool
    let remainingUses: Int
    let requiresLicense: Bool
    let registrationToken: String?
    let message: String
    let userStatus: String

    func toDict() -> [String: Any] {
        return [
            "device_id": deviceId,
            "registered": registered,
            "remaining_uses": remainingUses,
            "requires_license": requiresLicense,
            "registration_token": registrationToken ?? "",
            "message": message,
            "user_status": userStatus
        ]
    }
}

struct LicenseValidationResponse {
    let valid: Bool
    let expiresAt: Date?
    let userEmail: String?
    let licenseType: String?
    let errorMessage: String?
}

struct DeviceStatusResponse {
    let deviceId: String
    let remainingUses: Int
    let totalUsage: Int
    let requiresLicense: Bool
    let lastUsedAt: Date
    let status: String
}

struct UsageResponse {
    let remainingUses: Int
    let totalUsage: Int
    let requiresLicense: Bool
    let message: String
}

// MARK: - Result Types

enum DeviceRegistrationResult {
    case success(DeviceRegistrationResponse)
    case failure(String)
}

enum LicenseValidationResult {
    case success(LicenseValidationResponse)
    case failure(String)
}

enum DeviceStatusResult {
    case success(DeviceStatusResponse)
    case failure(String)
}

enum UsageResult {
    case success(UsageResponse)
    case failure(String)
}
