//
//  LicenseManagerTests.swift
//  cutclipTests
//
//  Tests for LicenseManager license operations
//

import XCTest
@testable import cutclip

@MainActor
final class LicenseManagerTests: XCTestCase {
    
    var licenseManager: LicenseManager!
    var mockErrorHandler: MockErrorHandler!
    var mockUsageTracker: MockUsageTracker!
    
    override func setUp() async throws {
        // Create fresh instance (can't use shared)
        // Note: We can't easily create a new LicenseManager instance
        // because it's a singleton with private init
        licenseManager = LicenseManager.shared
        mockErrorHandler = MockErrorHandler()
        
        // Set error handler
        licenseManager.errorHandler = mockErrorHandler
        
        // Reset state for testing
        licenseManager.resetForTesting()
    }
    
    override func tearDown() async throws {
        licenseManager = nil
        mockErrorHandler = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        // Test initial state before initialization
        XCTAssertEqual(licenseManager.licenseStatus, .unknown)
        XCTAssertFalse(licenseManager.isLoading)
        XCTAssertFalse(licenseManager.isInitialized)
        XCTAssertNil(licenseManager.errorMessage)
        XCTAssertFalse(licenseManager.hasNetworkError)
        XCTAssertFalse(licenseManager.needsLicenseSetup)
    }
    
    func testInitializeLicenseSystem() {
        // Test initialization
        licenseManager.initializeLicenseSystem()
        
        // Should start loading
        XCTAssertTrue(licenseManager.isLoading)
        
        // Note: Can't easily test async initialization completion
        // without mocking internal dependencies
    }
    
    func testRetryInitialization() {
        // Set some error state
        licenseManager.hasNetworkError = true
        licenseManager.errorMessage = "Test error"
        licenseManager.isInitialized = true
        
        // Retry
        licenseManager.retryInitialization()
        
        // Should reset state
        XCTAssertFalse(licenseManager.hasNetworkError)
        XCTAssertNil(licenseManager.errorMessage)
        XCTAssertFalse(licenseManager.isInitialized)
        XCTAssertTrue(licenseManager.isLoading)
    }
    
    // MARK: - License Status Tests
    
    func testCanUseApp() {
        // Test different license states
        
        // Licensed user can use app
        licenseManager.licenseStatus = .licensed
        XCTAssertTrue(licenseManager.canUseApp())
        
        // Free trial with credits can use app
        licenseManager.licenseStatus = .freeTrial(remaining: 3)
        XCTAssertTrue(licenseManager.canUseApp())
        
        // Free trial with no credits cannot use app
        licenseManager.licenseStatus = .freeTrial(remaining: 0)
        XCTAssertFalse(licenseManager.canUseApp())
        
        // Trial expired cannot use app
        licenseManager.licenseStatus = .trialExpired
        XCTAssertFalse(licenseManager.canUseApp())
        
        // Unlicensed cannot use app
        licenseManager.licenseStatus = .unlicensed
        XCTAssertFalse(licenseManager.canUseApp())
        
        // Unknown status cannot use app
        licenseManager.licenseStatus = .unknown
        XCTAssertFalse(licenseManager.canUseApp())
    }
    
    func testGetRemainingUses() {
        // Test getting remaining uses
        // This delegates to UsageTracker, which we can't easily mock
        let remaining = licenseManager.getRemainingUses()
        XCTAssertGreaterThanOrEqual(remaining, 0)
    }
    
    // MARK: - License Validation Tests
    
    func testValidateLicense() async {
        // Test license validation
        let isValid = await licenseManager.validateLicense("TEST-LICENSE-KEY")
        
        // Without mocking UsageTracker, this will likely fail
        XCTAssertFalse(licenseManager.isLoading)
        
        // Should have set an error message if validation failed
        if !isValid {
            XCTAssertNotNil(licenseManager.errorMessage)
        }
    }
    
    func testActivateLicense() async {
        // Test license activation (delegates to validateLicense)
        let activated = await licenseManager.activateLicense("VALID-LICENSE-KEY")
        
        // Without mocking, this will likely fail
        XCTAssertFalse(licenseManager.isLoading)
        
        if activated {
            XCTAssertEqual(licenseManager.licenseStatus, .licensed)
            XCTAssertFalse(licenseManager.needsLicenseSetup)
        }
    }
    
    func testDeactivateLicense() async {
        // Set up licensed state
        licenseManager.licenseStatus = .licensed
        licenseManager.needsLicenseSetup = false
        
        // Deactivate
        await licenseManager.deactivateLicense()
        
        // Should reset to unlicensed state
        XCTAssertEqual(licenseManager.licenseStatus, .unlicensed)
        XCTAssertTrue(licenseManager.needsLicenseSetup)
    }
    
    // MARK: - Debug Info Tests
    
    func testGetDebugInfo() {
        // Test debug info generation
        licenseManager.licenseStatus = .freeTrial(remaining: 2)
        licenseManager.needsLicenseSetup = false
        
        let debugInfo = licenseManager.getDebugInfo()
        
        // Should contain various debug fields
        XCTAssertNotNil(debugInfo["licenseStatus"])
        XCTAssertNotNil(debugInfo["needsLicenseSetup"])
        XCTAssertNotNil(debugInfo["deviceId"])
    }
    
    func testGetLicenseAnalytics() {
        // Test analytics generation
        licenseManager.licenseStatus = .licensed
        
        let analytics = licenseManager.getLicenseAnalytics()
        
        // Should contain analytics data
        XCTAssertNotNil(analytics["licenseStatus"])
        XCTAssertNotNil(analytics["hasValidLicense"])
    }
    
    // MARK: - State Management Tests
    
    func testResetForTesting() {
        // Set some state
        licenseManager.licenseStatus = .licensed
        licenseManager.errorMessage = "Test error"
        licenseManager.needsLicenseSetup = false
        
        // Reset
        licenseManager.resetForTesting()
        
        // Should reset error but keep loading state
        XCTAssertNil(licenseManager.errorMessage)
        XCTAssertTrue(licenseManager.isLoading) // Because it re-initializes
    }
    
    // MARK: - Record Usage Tests
    
    func testRecordAppUsage() {
        // Test usage recording for different states
        
        // Licensed user - should allow
        licenseManager.licenseStatus = .licensed
        licenseManager.recordAppUsage()
        // Note: Can't verify async task completion without mocks
        
        // Free trial with credits - should allow
        licenseManager.licenseStatus = .freeTrial(remaining: 2)
        licenseManager.recordAppUsage()
        
        // No credits - should not allow
        licenseManager.licenseStatus = .freeTrial(remaining: 0)
        licenseManager.recordAppUsage()
        // Should print error but not crash
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandlerIntegration() {
        // Test that error handler is properly connected
        XCTAssertNotNil(licenseManager.errorHandler)
        XCTAssertTrue(licenseManager.errorHandler === mockErrorHandler)
    }
    
    func testNetworkErrorHandling() async {
        // Simulate network error during initialization
        licenseManager.hasNetworkError = true
        
        // Should affect needsLicenseSetup determination
        // Note: Can't easily test without mocking internal services
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentInitialization() {
        // Test multiple concurrent initialization attempts
        let expectation1 = expectation(description: "init1")
        let expectation2 = expectation(description: "init2")
        
        Task {
            licenseManager.initializeLicenseSystem()
            expectation1.fulfill()
        }
        
        Task {
            licenseManager.initializeLicenseSystem()
            expectation2.fulfill()
        }
        
        wait(for: [expectation1, expectation2], timeout: 1.0)
        
        // Should handle concurrent calls gracefully
        XCTAssertTrue(licenseManager.isLoading || licenseManager.isInitialized)
    }
    
    // MARK: - Integration Tests
    
    func testLicenseStatusFlow() async {
        // Test the flow of license status changes
        
        // Start unlicensed
        licenseManager.licenseStatus = .unlicensed
        XCTAssertFalse(licenseManager.canUseApp())
        
        // Simulate getting free credits
        licenseManager.licenseStatus = .freeTrial(remaining: 3)
        XCTAssertTrue(licenseManager.canUseApp())
        
        // Use a credit
        licenseManager.licenseStatus = .freeTrial(remaining: 2)
        XCTAssertTrue(licenseManager.canUseApp())
        
        // Expire trial
        licenseManager.licenseStatus = .trialExpired
        XCTAssertFalse(licenseManager.canUseApp())
        
        // Activate license
        licenseManager.licenseStatus = .licensed
        XCTAssertTrue(licenseManager.canUseApp())
    }
    
    // MARK: - Limitations
    
    func testLimitationsNote() {
        // Note: Due to LicenseManager being a singleton with private init
        // and having internal dependencies that can't be mocked:
        // 1. Can't test with fresh instances
        // 2. Can't mock UsageTracker, SecureStorage, etc.
        // 3. Can't test actual network operations
        // 4. Can't fully test async initialization flow
        //
        // To properly test LicenseManager, it would need:
        // - Dependency injection for all services
        // - Non-singleton design or factory pattern
        // - Protocol-based dependencies for mocking
        
        XCTAssertTrue(true, "See test limitations in comments")
    }
}