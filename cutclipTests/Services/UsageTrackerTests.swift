//
//  UsageTrackerTests.swift
//  cutclipTests
//
//  Integration tests for UsageTracker and its extracted services
//

import XCTest
@testable import cutclip

@MainActor
final class UsageTrackerTests: XCTestCase {
    
    var usageTracker: UsageTracker!
    var mockURLSession: MockURLSession!
    var cacheService: CacheService!
    var apiClient: APIClient!
    
    override func setUp() async throws {
        // Create mock URL session
        mockURLSession = MockURLSession()
        
        // Create real services with mock session
        cacheService = CacheService()
        apiClient = APIClient(session: mockURLSession)
        
        let deviceRepo = DeviceRepository(apiClient: apiClient, cacheService: cacheService)
        let licenseRepo = LicenseRepository(apiClient: apiClient, cacheService: cacheService)
        
        // Create usage tracker with real services
        usageTracker = UsageTracker(
            cacheService: cacheService,
            apiClient: apiClient,
            deviceRepository: deviceRepo,
            licenseRepository: licenseRepo
        )
        
        // Clear any cached data
        await cacheService.clearCache()
    }
    
    override func tearDown() async throws {
        usageTracker = nil
        mockURLSession = nil
        cacheService = nil
        apiClient = nil
    }
    
    // MARK: - Device Status Tests
    
    func testCheckDeviceStatusSuccess() async throws {
        // Given: Mock successful device status response
        let deviceData = TestDataBuilder.makeDeviceResponse(
            deviceId: "test-device-123",
            freeCredits: 2,
            isActive: true
        )
        
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/check-device?device_id=\(usageTracker.deviceId)")!
        
        mockURLSession.addMockResponse(
            for: url,
            data: deviceData,
            statusCode: 200
        )
        
        // When: Check device status
        try await usageTracker.checkDeviceStatus()
        
        // Then: State should be updated
        XCTAssertEqual(usageTracker.freeCredits, 2)
        XCTAssertTrue(usageTracker.isActive)
        XCTAssertEqual(mockURLSession.requestCount, 1)
    }
    
    func testCheckDeviceStatusUsesCache() async throws {
        // Given: Mock device status response
        let deviceData = TestDataBuilder.makeDeviceResponse(freeCredits: 5)
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/check-device?device_id=\(usageTracker.deviceId)")!
        
        mockURLSession.addMockResponse(for: url, data: deviceData)
        
        // When: Check device status twice
        try await usageTracker.checkDeviceStatus()
        try await usageTracker.checkDeviceStatus()
        
        // Then: Should only make one network request (second uses cache)
        XCTAssertEqual(mockURLSession.requestCount, 1)
        XCTAssertEqual(usageTracker.freeCredits, 5)
    }
    
    func testCheckDeviceStatusForceRefresh() async throws {
        // Given: Mock device status response
        let deviceData = TestDataBuilder.makeDeviceResponse(freeCredits: 5)
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/check-device?device_id=\(usageTracker.deviceId)")!
        
        mockURLSession.addMockResponse(for: url, data: deviceData)
        
        // When: Check device status with force refresh
        try await usageTracker.checkDeviceStatus()
        try await usageTracker.checkDeviceStatus(forceRefresh: true)
        
        // Then: Should make two network requests
        XCTAssertEqual(mockURLSession.requestCount, 2)
    }
    
    func testCheckDeviceStatusNetworkError() async {
        // Given: Network error
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/check-device?device_id=\(usageTracker.deviceId)")!
        
        mockURLSession.addMockResponse(
            for: url,
            error: URLError(.notConnectedToInternet)
        )
        
        // When/Then: Should throw network error
        await assertThrowsError(
            try await usageTracker.checkDeviceStatus(forceRefresh: true),
            expectedError: AppError.network("The request timed out.")
        )
    }
    
    // MARK: - Device Creation Tests
    
    func testCreateDeviceSuccess() async throws {
        // Given: Mock successful device creation
        let deviceData = TestDataBuilder.makeDeviceResponse(
            deviceId: "new-device-123",
            freeCredits: 5
        )
        
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/create-device")!
        
        mockURLSession.addMockResponse(
            for: url,
            data: deviceData,
            statusCode: 201
        )
        
        // When: Create device
        try await usageTracker.createDevice()
        
        // Then: State should be updated
        XCTAssertEqual(usageTracker.freeCredits, 5)
        XCTAssertTrue(usageTracker.isActive)
        XCTAssertEqual(mockURLSession.requestCount, 1)
        
        // Verify request had correct method
        XCTAssertEqual(mockURLSession.lastRequest?.httpMethod, "POST")
    }
    
    // MARK: - Credit Decrement Tests
    
    func testDecrementFreeCreditsSuccess() async throws {
        // Given: Device with credits
        usageTracker.freeCredits = 2
        
        let responseData = """
        {
            "success": true,
            "remaining_credits": 1
        }
        """.data(using: .utf8)!
        
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/decrement-free-credits")!
        
        mockURLSession.addMockResponse(
            for: url,
            data: responseData,
            statusCode: 200
        )
        
        // When: Decrement credits
        try await usageTracker.decrementFreeCredits()
        
        // Then: Credits should be decremented
        XCTAssertEqual(usageTracker.freeCredits, 1)
        XCTAssertEqual(mockURLSession.lastRequest?.httpMethod, "PUT")
    }
    
    func testDecrementFreeCreditsNoCredits() async {
        // Given: No credits remaining
        usageTracker.freeCredits = 0
        
        // When/Then: Should throw error
        await assertThrowsError(
            try await usageTracker.decrementFreeCredits(),
            expectedError: AppError.noCreditsRemaining
        )
        
        // Should not make network request
        XCTAssertEqual(mockURLSession.requestCount, 0)
    }
    
    // MARK: - License Validation Tests
    
    func testValidateLicenseSuccess() async throws {
        // Given: Valid license response
        let licenseData = TestDataBuilder.makeLicenseResponse(
            key: "VALID-LICENSE-KEY",
            isValid: true
        )
        
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/validate-license")!
        
        mockURLSession.addMockResponse(
            for: url,
            data: licenseData,
            statusCode: 200
        )
        
        // When: Validate license
        let isValid = try await usageTracker.validateLicense("VALID-LICENSE-KEY")
        
        // Then: Should return true
        XCTAssertTrue(isValid)
        XCTAssertEqual(mockURLSession.requestCount, 1)
    }
    
    func testValidateLicenseInvalid() async throws {
        // Given: Invalid license response
        let licenseData = TestDataBuilder.makeLicenseResponse(
            key: "INVALID-KEY",
            isValid: false
        )
        
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/validate-license")!
        
        mockURLSession.addMockResponse(
            for: url,
            data: licenseData,
            statusCode: 200
        )
        
        // When: Validate license
        let isValid = try await usageTracker.validateLicense("INVALID-KEY")
        
        // Then: Should return false
        XCTAssertFalse(isValid)
    }
    
    // MARK: - Integration Tests
    
    func testFullDeviceLifecycle() async throws {
        // Test complete device lifecycle: create -> use -> decrement
        
        // 1. Create device
        let createData = TestDataBuilder.makeDeviceResponse(freeCredits: 5)
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        mockURLSession.addMockResponse(
            for: URL(string: "\(baseURL)/users/create-device")!,
            data: createData,
            statusCode: 201
        )
        
        try await usageTracker.createDevice()
        XCTAssertEqual(usageTracker.freeCredits, 5)
        
        // 2. Check status
        let statusData = TestDataBuilder.makeDeviceResponse(freeCredits: 5)
        mockURLSession.addMockResponse(
            for: URL(string: "\(baseURL)/users/check-device?device_id=\(usageTracker.deviceId)")!,
            data: statusData
        )
        
        try await usageTracker.checkDeviceStatus(forceRefresh: true)
        XCTAssertEqual(usageTracker.freeCredits, 5)
        
        // 3. Decrement credits
        let decrementData = """
        {"success": true, "remaining_credits": 2}
        """.data(using: .utf8)!
        mockURLSession.addMockResponse(
            for: URL(string: "\(baseURL)/users/decrement-free-credits")!,
            data: decrementData
        )
        
        try await usageTracker.decrementFreeCredits()
        XCTAssertEqual(usageTracker.freeCredits, 2)
    }
    
    // MARK: - Cache Service Integration Tests
    
    func testCacheServiceIntegration() async throws {
        // Test that cache service properly caches API responses
        
        // Given: Device status response
        let deviceData = TestDataBuilder.makeDeviceResponse(freeCredits: 5)
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/check-device?device_id=\(usageTracker.deviceId)")!
        
        mockURLSession.addMockResponse(for: url, data: deviceData)
        
        // When: Check status multiple times
        try await usageTracker.checkDeviceStatus()
        
        // Clear URL session to ensure cache is used
        mockURLSession.responses.removeAll()
        
        // This should use cache
        try await usageTracker.checkDeviceStatus()
        
        // Then: Should still have the data from cache
        XCTAssertEqual(usageTracker.freeCredits, 5)
    }
    
    // MARK: - Error Recovery Tests
    
    func testRetryLogicOnNetworkFailure() async throws {
        // Test that retry logic works for transient failures
        
        let baseURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "https://cutclip.moinulmoin.com/api"
        let url = URL(string: "\(baseURL)/users/check-device?device_id=\(usageTracker.deviceId)")!
        
        // First two attempts fail, third succeeds
        var callCount = 0
        mockURLSession.responses[url] = { () -> (Data?, URLResponse?, Error?) in
            callCount += 1
            if callCount < 3 {
                return (nil, nil, URLError(.timedOut))
            } else {
                let data = TestDataBuilder.makeDeviceResponse(freeCredits: 2)
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (data, response, nil)
            }
        }()
        
        // When: Check device status (should retry and eventually succeed)
        try await usageTracker.checkDeviceStatus(forceRefresh: true)
        
        // Then: Should have succeeded after retries
        XCTAssertEqual(usageTracker.freeCredits, 2)
    }
}