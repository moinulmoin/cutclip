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
        let url = URL(string: "https://api.cutclip.com/v1/users/check")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer your-api-key", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "device_id": deviceId,
            "timestamp": ISO8601DateFormatter().string(from: Date())
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

        return UserCheckResponse(
            exists: json?["exists"] as? Bool ?? false,
            userId: json?["user_id"] as? String,
            remainingUses: json?["remaining_uses"] as? Int ?? 0,
            totalUsage: json?["total_usage"] as? Int ?? 0,
            hasLicense: json?["has_license"] as? Bool ?? false,
            licenseStatus: json?["license_status"] as? String,
            quotaComplete: json?["quota_complete"] as? Bool ?? false
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
        let url = URL(string: "https://api.cutclip.com/v1/users/create")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer your-api-key", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "device_id": deviceId,
            "device_info": deviceInfo,
            "app_version": deviceInfo["app_version"] ?? "1.0.0",
            "start_trial": true,
            "trial_uses": 3,
            "timestamp": ISO8601DateFormatter().string(from: Date())
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

        return DeviceRegistrationResponse(
            deviceId: json?["device_id"] as? String ?? deviceId,
            registered: json?["created"] as? Bool ?? false,
            remainingUses: json?["remaining_uses"] as? Int ?? 3,
            requiresLicense: false,
            registrationToken: json?["registration_token"] as? String,
            message: json?["message"] as? String ?? "Account created with 3 free uses",
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
        let url = URL(string: "https://api.cutclip.com/v1/users/\(deviceId)/usage")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer your-api-key", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "action": "video_clip",
            "timestamp": ISO8601DateFormatter().string(from: Date())
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

        return UsageResponse(
            remainingUses: json?["remaining_uses"] as? Int ?? 0,
            totalUsage: json?["total_usage"] as? Int ?? 0,
            requiresLicense: json?["requires_license"] as? Bool ?? false,
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
        let url = URL(string: "https://api.cutclip.com/v1/licenses/validate")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer your-api-key", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "license_key": licenseKey,
            "device_id": deviceId,
            "app_version": appVersion,
            "timestamp": ISO8601DateFormatter().string(from: Date())
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

        let expiresAtString = json?["expires_at"] as? String
        let expiresAt = expiresAtString.flatMap { ISO8601DateFormatter().date(from: $0) }

        return LicenseValidationResponse(
            valid: json?["valid"] as? Bool ?? false,
            expiresAt: expiresAt,
            userEmail: json?["user_email"] as? String,
            licenseType: json?["license_type"] as? String,
            errorMessage: json?["error_message"] as? String
        )
    }

    private func callCheckDeviceStatusAPI(deviceId: String) async throws -> DeviceStatusResponse {
        let url = URL(string: "https://api.cutclip.com/v1/devices/\(deviceId)/status")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer your-api-key", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let lastUsedString = json?["last_used_at"] as? String
        let lastUsedAt = lastUsedString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        return DeviceStatusResponse(
            deviceId: json?["device_id"] as? String ?? deviceId,
            remainingUses: json?["remaining_uses"] as? Int ?? 0,
            totalUsage: json?["total_usage"] as? Int ?? 0,
            requiresLicense: json?["requires_license"] as? Bool ?? true,
            lastUsedAt: lastUsedAt,
            status: json?["status"] as? String ?? "unknown"
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
