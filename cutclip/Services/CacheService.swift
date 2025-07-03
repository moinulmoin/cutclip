//
//  CacheService.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Thread-safe cache service for device data
public actor CacheService {
    private var lastFetchTime: Date?
    private var lastInvalidationTime: Date?
    private var lastCreditUpdateTime: Date?
    private var cachedData: DeviceData?
    private let defaultCacheValidity: TimeInterval = 10 * 60 // 10 minutes
    
    public init() {}
    
    /// Get cached data if it's still valid
    public func getCachedData(maxAge: TimeInterval? = nil) -> (data: DeviceData, age: TimeInterval)? {
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
    
    /// Store data in cache
    public func setCachedData(_ data: DeviceData) {
        self.cachedData = data
        self.lastFetchTime = Date()
    }
    
    /// Invalidate the cache
    public func invalidate() {
        self.cachedData = nil
        self.lastFetchTime = nil
        self.lastInvalidationTime = Date()
        print("🗑️ Cache invalidated")
    }
    
    /// Check if cache was recently invalidated
    public func hasRecentInvalidation() -> Bool {
        guard let invalidationTime = lastInvalidationTime else { return false }
        return Date().timeIntervalSince(invalidationTime) < 120 // 2 minutes
    }
    
    /// Update only the credits in cached data
    public func updateCredits(_ newCredits: Int) {
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
    
    /// Check if credits were recently updated
    public func hasRecentCreditUpdate() -> Bool {
        guard let updateTime = lastCreditUpdateTime else { return false }
        return Date().timeIntervalSince(updateTime) < 120 // 2 minutes
    }
    
    /// Calculate cache validity based on usage patterns and license status
    public func getCacheValidityForUsage(hasLicense: Bool, currentCredits: Int) -> TimeInterval {
        // Check if there was a recent cache invalidation (state change)
        if hasRecentInvalidation() {
            return 0 // Force fresh data after state changes
        }
        
        // No cache during critical operations or for trial users close to limit
        if currentCredits <= 1 && !hasLicense {
            return 30 // 30 seconds for users about to expire
        }
        
        // Check if user just used credits (force fresh check)
        if hasRecentCreditUpdate() {
            return 60 // 1 minute after credit usage
        }
        
        // Longer cache for licensed users, shorter for free users
        return hasLicense ? (10 * 60) : (3 * 60) // 10 minutes : 3 minutes
    }
}