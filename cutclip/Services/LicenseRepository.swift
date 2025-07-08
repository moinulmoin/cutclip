//
//  LicenseRepository.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Repository for license validation operations
@MainActor
public class LicenseRepository {
    private let baseURL: String = APIConfiguration.baseURL
    private let deviceRepository: DeviceRepository
    private let cacheService: CacheService
    
    public init(deviceRepository: DeviceRepository, cacheService: CacheService) {
        self.deviceRepository = deviceRepository
        self.cacheService = cacheService
    }
    
    /// POST /api/validate-license
    public func validateLicense(licenseKey: String) async throws -> LicenseValidationResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()
        
        // 1. Call validation API
        let validationResult = try await callValidateLicenseAPI(licenseKey: licenseKey, deviceId: deviceId)
        
        if validationResult.valid {
            // 2. If valid, update device on backend to link license
            _ = try await deviceRepository.updateDeviceLicense(licenseKey)
            
            // 3. Update local secure storage
            let stored = SecureStorage.shared.storeLicense(licenseKey, deviceID: deviceId)
            if !stored {
                print("⚠️ Failed to store license key locally after validation")
                // This is not a fatal error, as server holds the truth
            }
            
            // 4. Invalidate cache to force a fresh state
            await cacheService.invalidate()
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
                    do {
                        if let errorResponse = try? JSONDecoder().decode(LicenseErrorResponse.self, from: data) {
                            throw UsageError.licenseError(errorResponse.message)
                        }
                    } catch {
                        // Ignore JSON decode errors and throw generic error
                    }
                    
                    // Special handling for known license errors
                    switch httpResponse.statusCode {
                    case 404:
                        throw UsageError.licenseError("License key not found")
                    case 409:
                        throw UsageError.licenseError("License is already in use on another device")
                    case 410:
                        throw UsageError.licenseError("License has been revoked")
                    default:
                        throw UsageError.licenseError("Invalid license key")
                    }
                }
                throw UsageError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }
            
            return try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
        }
    }
    
    // MARK: - License Status Methods
    
    /// Check if there's a valid license stored locally
    public func hasStoredLicense() -> Bool {
        return SecureStorage.shared.hasValidLicense()
    }
    
    /// Get the stored license key if available
    public func getStoredLicense() -> String? {
        return SecureStorage.shared.retrieveLicense()?.key
    }
    
    /// Clear stored license
    public func clearStoredLicense() {
        _ = SecureStorage.shared.deleteLicense()
    }
}