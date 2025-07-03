//
//  CacheServiceTests.swift
//  cutclipTests
//
//  Tests for CacheService concurrent operations and caching logic
//

import XCTest
@testable import cutclip

final class CacheServiceTests: XCTestCase {
    
    var cacheService: CacheService!
    
    override func setUp() async throws {
        cacheService = CacheService()
    }
    
    override func tearDown() async throws {
        cacheService = nil
    }
    
    // MARK: - Basic Cache Operations
    
    func testCacheStorage() async {
        // Given: Test device data
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        
        // When: Store in cache
        await cacheService.setCachedData(deviceData)
        
        // Then: Should retrieve from cache
        let cached = await cacheService.getCachedData()
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.data.id, "123")
        XCTAssertEqual(cached?.data.deviceId, "device-123")
        XCTAssertEqual(cached?.data.freeCredits, 3)
        XCTAssertLessThan(cached?.age ?? 999, 1.0) // Should be very recent
    }
    
    func testCacheExpiry() async {
        // Given: Cached data
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        
        // When: Request with very short max age
        let cached = await cacheService.getCachedData(maxAge: 0.001) // 1ms
        
        // Wait a bit
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Then: Should be expired
        let expiredCache = await cacheService.getCachedData(maxAge: 0.001)
        XCTAssertNil(expiredCache)
    }
    
    func testCacheInvalidation() async {
        // Given: Cached data
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        
        // Verify cache exists
        let beforeInvalidation = await cacheService.getCachedData()
        XCTAssertNotNil(beforeInvalidation)
        
        // When: Invalidate cache
        await cacheService.invalidate()
        
        // Then: Cache should be empty
        let afterInvalidation = await cacheService.getCachedData()
        XCTAssertNil(afterInvalidation)
    }
    
    // MARK: - Credit Update Tests
    
    func testCreditUpdate() async {
        // Given: Initial cached data
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        
        // When: Update credits
        await cacheService.updateCredits(2)
        
        // Then: Credits should be updated
        let cached = await cacheService.getCachedData()
        XCTAssertEqual(cached?.data.freeCredits, 2)
        
        // And recent credit update should be true
        let hasRecentUpdate = await cacheService.hasRecentCreditUpdate()
        XCTAssertTrue(hasRecentUpdate)
    }
    
    func testCreditUpdateNoChange() async {
        // Given: Initial cached data
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        
        // When: Update with same credits
        await cacheService.updateCredits(3)
        
        // Then: Should not mark as recent update
        let hasRecentUpdate = await cacheService.hasRecentCreditUpdate()
        XCTAssertFalse(hasRecentUpdate)
    }
    
    // MARK: - Invalidation State Tests
    
    func testRecentInvalidation() async {
        // Initially no recent invalidation
        let initialState = await cacheService.hasRecentInvalidation()
        XCTAssertFalse(initialState)
        
        // When: Invalidate cache
        await cacheService.invalidate()
        
        // Then: Should have recent invalidation
        let afterInvalidation = await cacheService.hasRecentInvalidation()
        XCTAssertTrue(afterInvalidation)
    }
    
    // MARK: - Cache Validity Tests
    
    func testCacheValidityForLicensedUser() async {
        // Test licensed user gets longer cache validity
        let validity = await cacheService.getCacheValidityForUsage(
            hasLicense: true,
            currentCredits: 10
        )
        
        XCTAssertEqual(validity, 600) // 10 minutes
    }
    
    func testCacheValidityForFreeUser() async {
        // Test free user gets shorter cache validity
        let validity = await cacheService.getCacheValidityForUsage(
            hasLicense: false,
            currentCredits: 3
        )
        
        XCTAssertEqual(validity, 180) // 3 minutes
    }
    
    func testCacheValidityForUserNearLimit() async {
        // Test user with 1 credit left gets very short cache
        let validity = await cacheService.getCacheValidityForUsage(
            hasLicense: false,
            currentCredits: 1
        )
        
        XCTAssertEqual(validity, 30) // 30 seconds
    }
    
    func testCacheValidityAfterRecentInvalidation() async {
        // Given: Recent invalidation
        await cacheService.invalidate()
        
        // When: Check validity
        let validity = await cacheService.getCacheValidityForUsage(
            hasLicense: true,
            currentCredits: 10
        )
        
        // Then: Should force fresh data
        XCTAssertEqual(validity, 0)
    }
    
    func testCacheValidityAfterCreditUpdate() async {
        // Given: Recent credit update
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        await cacheService.updateCredits(2)
        
        // When: Check validity
        let validity = await cacheService.getCacheValidityForUsage(
            hasLicense: false,
            currentCredits: 2
        )
        
        // Then: Should have short validity after credit usage
        XCTAssertEqual(validity, 60) // 1 minute
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentCacheAccess() async {
        // Test multiple concurrent reads and writes
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        
        // Perform concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Multiple writers
            for i in 1...5 {
                group.addTask {
                    var data = deviceData
                    data.freeCredits = i
                    await self.cacheService.setCachedData(data)
                }
            }
            
            // Multiple readers
            for _ in 1...10 {
                group.addTask {
                    _ = await self.cacheService.getCachedData()
                }
            }
            
            // Credit updates
            for i in 1...3 {
                group.addTask {
                    await self.cacheService.updateCredits(i)
                }
            }
            
            // Invalidations
            group.addTask {
                await self.cacheService.invalidate()
            }
        }
        
        // Should complete without crashes or deadlocks
        XCTAssertTrue(true)
    }
    
    func testConcurrentCreditUpdates() async {
        // Test concurrent credit updates
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 10,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        
        // Perform many concurrent credit updates
        await withTaskGroup(of: Void.self) { group in
            for i in 1...100 {
                group.addTask {
                    await self.cacheService.updateCredits(i % 10)
                }
            }
        }
        
        // Should have some value between 0-9
        let cached = await cacheService.getCachedData()
        XCTAssertNotNil(cached)
        XCTAssertGreaterThanOrEqual(cached?.data.freeCredits ?? -1, 0)
        XCTAssertLessThan(cached?.data.freeCredits ?? 10, 10)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyCacheOperations() async {
        // Test operations on empty cache
        
        // Get from empty cache
        let empty = await cacheService.getCachedData()
        XCTAssertNil(empty)
        
        // Update credits with no cached data
        await cacheService.updateCredits(5)
        
        // Should still be empty
        let stillEmpty = await cacheService.getCachedData()
        XCTAssertNil(stillEmpty)
        
        // No recent credit update since there was no data
        let hasUpdate = await cacheService.hasRecentCreditUpdate()
        XCTAssertFalse(hasUpdate)
    }
    
    func testDefaultCacheValidity() async {
        // Given: Cached data
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        
        // When: Get cached data without specifying max age
        let cached = await cacheService.getCachedData()
        
        // Then: Should use default validity (10 minutes)
        XCTAssertNotNil(cached)
        
        // Test that it respects the default
        let cachedWithDefault = await cacheService.getCachedData(maxAge: 600) // 10 minutes
        XCTAssertNotNil(cachedWithDefault)
    }
    
    // MARK: - Performance Tests
    
    func testCachePerformance() async throws {
        // Measure cache operations performance
        let deviceData = DeviceData(
            id: "123",
            deviceId: "device-123",
            freeCredits: 3,
            user: nil
        )
        
        measure {
            Task {
                // Perform many cache operations
                for _ in 1...1000 {
                    await cacheService.setCachedData(deviceData)
                    _ = await cacheService.getCachedData()
                    await cacheService.updateCredits(Int.random(in: 1...10))
                }
            }
        }
    }
}