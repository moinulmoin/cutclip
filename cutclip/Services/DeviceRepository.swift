//
//  DeviceRepository.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Repository for all device-related API operations
@MainActor
public class DeviceRepository {
    private let apiClient = APIClient()
    private let cacheService: CacheService
    private let baseURL: String = APIConfiguration.baseURL
    
    // Callbacks for state updates
    public var onCreditsUpdate: (@MainActor @Sendable (Int, Bool) -> Void)?
    public var onLoadingStateChange: (@MainActor @Sendable (Bool) -> Void)?
    
    public init(cacheService: CacheService) {
        self.cacheService = cacheService
    }
    
    // MARK: - Device API Methods
    
    /// GET /api/users/check-device (with smart caching)
    public func checkDeviceStatus(forceRefresh: Bool = false) async throws -> UsageDeviceStatusResponse {
        // Check if we can use cached data
        if !forceRefresh {
            let cacheValidity = await getCacheValidity()
            if let cachedResult = await cacheService.getCachedData(maxAge: cacheValidity) {
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
        
        onLoadingStateChange?(true)
        defer { onLoadingStateChange?(false) }
        
        let request = APIConfiguration.createRequest(url: url)
        
        do {
            let result = try await apiClient.performRequest(
                request,
                expecting: DeviceCheckResponse.self,
                onRetry: { attempt, error in
                    print("⚠️ Check device status failed on attempt \(attempt)/3: \(error.localizedDescription)")
                }
            )
            
            if let deviceData = result.data {
                // Notify about credits update
                onCreditsUpdate?(deviceData.freeCredits, deviceData.freeCredits <= 0 && !hasValidLicense(deviceData.user?.license))
                
                // Cache the successful response (thread-safe)
                await cacheService.setCachedData(deviceData)
                return .found(deviceData)
            } else {
                return .notFound
            }
        } catch {
            // Invalidate cache on network errors to prevent stale data
            if error is URLError {
                await cacheService.invalidate()
                print("🗑️ Cache invalidated due to network errors")
            }
            print("❌ Check device status failed after 3 attempts")
            throw error
        }
    }
    
    /// POST /api/users/create-device (Create device only - no user until license)
    public func createDeviceOnly() async throws -> CreateDeviceResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()
        
        let urlString = "\(baseURL)\(APIConfiguration.Endpoints.createDevice)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }
        
        let body = CreateDeviceRequest(
            deviceId: deviceId,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: "Mac"
        )
        let bodyData = try JSONEncoder().encode(body)
        let request = APIConfiguration.createRequest(url: url, method: "POST", body: bodyData)
        
        onLoadingStateChange?(true)
        defer { onLoadingStateChange?(false) }
        
        let result = try await apiClient.performRequest(
            request,
            expecting: CreateDeviceResponse.self,
            onRetry: { attempt, error in
                print("⚠️ Create device failed on attempt \(attempt)/3: \(error.localizedDescription)")
            }
        )
        
        // New devices get 5 free credits
        onCreditsUpdate?(5, false)
        
        // Invalidate cache after creating new device
        await cacheService.invalidate()
        print("🗑️ Cache invalidated after creating new device")
        print("📱 Device created with 5 free credits")
        
        return result
    }
    
    /// PUT /api/users/update-device (Creates user when license is added)
    public func updateDeviceLicense(_ license: String) async throws -> UpdateDeviceResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()
        
        let urlString = "\(baseURL)\(APIConfiguration.Endpoints.updateDevice)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }
        
        let body = UpdateDeviceRequest(deviceId: deviceId, license: license)
        let bodyData = try JSONEncoder().encode(body)
        let request = APIConfiguration.createRequest(url: url, method: "PUT", body: bodyData)
        
        onLoadingStateChange?(true)
        defer { onLoadingStateChange?(false) }
        
        let result = try await apiClient.performRequest(
            request,
            expecting: UpdateDeviceResponse.self,
            onRetry: { attempt, error in
                print("⚠️ Update device license failed on attempt \(attempt)/3: \(error.localizedDescription)")
            }
        )
        
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
    }
    
    /// PUT /api/users/decrement-free-credits (Only used for devices without license)
    public func decrementFreeCredits() async throws -> DecrementCreditsResponse {
        let deviceId = DeviceIdentifier.shared.getDeviceID()
        
        let urlString = "\(baseURL)\(APIConfiguration.Endpoints.decrementCredits)"
        guard let url = URL(string: urlString) else {
            throw UsageError.invalidURL
        }
        
        let body = DecrementCreditsRequest(deviceId: deviceId)
        let bodyData = try JSONEncoder().encode(body)
        let request = APIConfiguration.createRequest(url: url, method: "PUT", body: bodyData)
        
        onLoadingStateChange?(true)
        defer { onLoadingStateChange?(false) }
        
        do {
            let result = try await apiClient.performRequestWithCustomHandling(
                request,
                expecting: DecrementCreditsResponse.self,
                onRetry: { attempt, error in
                    print("⚠️ Decrement credits failed on attempt \(attempt)/3: \(error.localizedDescription)")
                },
                shouldRetry: { error in
                    // Don't retry business logic errors like insufficient credits
                    if let usageError = error as? UsageError,
                       case .insufficientCredits = usageError {
                        return false
                    }
                    return true
                },
                handleResponse: { statusCode, data in
                    let result = try JSONDecoder().decode(DecrementCreditsResponse.self, from: data)
                    
                    if statusCode == 200 {
                        if let deviceData = result.data?.device {
                            // Update credits and notify
                            await self.onCreditsUpdate?(
                                deviceData.freeCredits,
                                deviceData.freeCredits <= 0 && !SecureStorage.shared.hasValidLicense()
                            )
                            
                            // Update cache with new credit count (thread-safe)
                            await self.cacheService.updateCredits(deviceData.freeCredits)
                            
                            print("📊 Free credits decremented: \(deviceData.freeCredits) remaining")
                        }
                        return result
                    } else if statusCode == 400 {
                        // Insufficient credits - don't retry this error
                        await self.onCreditsUpdate?(0, true)
                        throw UsageError.insufficientCredits(result.message)
                    } else {
                        throw UsageError.serverError(statusCode)
                    }
                }
            )
            
            return result
        } catch {
            // Invalidate cache on network errors to force fresh fetch next time
            if error is URLError {
                await cacheService.invalidate()
                print("🗑️ Cache invalidated due to decrement credits network error")
            }
            print("❌ Decrement credits failed after 3 attempts")
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    private func hasValidLicense(_ license: String?) -> Bool {
        guard let license = license, !license.isEmpty else { return false }
        return true
    }
    
    private func getCacheValidity() async -> TimeInterval {
        // Get current credits from cached data or default to max
        let currentCredits = (await cacheService.getCachedData()?.data.freeCredits) ?? 3
        let hasLicense = SecureStorage.shared.hasValidLicense()
        
        return await cacheService.getCacheValidityForUsage(
            hasLicense: hasLicense,
            currentCredits: currentCredits
        )
    }
}