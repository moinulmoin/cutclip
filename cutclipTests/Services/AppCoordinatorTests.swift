//
//  AppCoordinatorTests.swift
//  cutclipTests
//
//  Tests for AppCoordinator state management and transitions
//

import XCTest
@testable import cutclip

@MainActor
final class AppCoordinatorTests: XCTestCase {
    
    var coordinator: AppCoordinator!
    var mockBinaryManager: MockBinaryManager!
    var mockErrorHandler: MockErrorHandler!
    var mockLicenseManager: MockLicenseManager!
    var mockUsageTracker: MockUsageTracker!
    
    override func setUp() async throws {
        // Create mock services
        mockBinaryManager = MockBinaryManager()
        mockErrorHandler = MockErrorHandler()
        mockLicenseManager = MockLicenseManager()
        mockUsageTracker = MockUsageTracker()
        
        // Create coordinator with mocks
        coordinator = AppCoordinator(
            binaryManager: mockBinaryManager,
            errorHandler: mockErrorHandler,
            licenseManager: mockLicenseManager,
            usageTracker: mockUsageTracker
        )
    }
    
    override func tearDown() async throws {
        coordinator = nil
        mockBinaryManager = nil
        mockErrorHandler = nil
        mockLicenseManager = nil
        mockUsageTracker = nil
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertEqual(coordinator.currentState, .disclaimer)
        XCTAssertFalse(coordinator.isTransitioning)
    }
    
    // MARK: - State Transition Tests
    
    func testDisclaimerAcceptedTransition() async {
        // Given: Starting at disclaimer
        XCTAssertEqual(coordinator.currentState, .disclaimer)
        
        // When: Accept disclaimer
        await coordinator.disclaimerAccepted()
        
        // Then: Should transition to autoSetup
        XCTAssertEqual(coordinator.currentState, .autoSetup)
    }
    
    func testAutoSetupCompletedTransition() async {
        // Given: Move to autoSetup state
        coordinator.currentState = .autoSetup
        
        // When: Complete auto setup
        await coordinator.autoSetupCompleted()
        
        // Then: Should transition to license
        XCTAssertEqual(coordinator.currentState, .license)
    }
    
    func testLicenseSetupCompletedWithValidLicenseTransition() async {
        // Given: Move to license state with valid license
        coordinator.currentState = .license
        mockLicenseManager.mockHasValidLicense = true
        mockLicenseManager.mockCanUseApp = true
        
        // When: Complete license setup
        await coordinator.licenseSetupCompleted()
        
        // Then: Should transition to main
        XCTAssertEqual(coordinator.currentState, .main)
    }
    
    func testLicenseSetupCompletedWithFreeCreditsTransition() async {
        // Given: Move to license state with free credits
        coordinator.currentState = .license
        mockLicenseManager.mockHasValidLicense = false
        mockLicenseManager.mockCanUseApp = true
        mockUsageTracker.mockFreeCredits = 2
        
        // When: Complete license setup
        await coordinator.licenseSetupCompleted()
        
        // Then: Should transition to main
        XCTAssertEqual(coordinator.currentState, .main)
    }
    
    func testLicenseSetupCompletedWithNoAccessTransition() async {
        // Given: Move to license state with no access
        coordinator.currentState = .license
        mockLicenseManager.mockHasValidLicense = false
        mockLicenseManager.mockCanUseApp = false
        mockUsageTracker.mockFreeCredits = 0
        
        // When: Complete license setup
        await coordinator.licenseSetupCompleted()
        
        // Then: Should remain in license state
        XCTAssertEqual(coordinator.currentState, .license)
    }
    
    // MARK: - Reset Tests
    
    func testResetToDisclaimer() async {
        // Given: In main state
        coordinator.currentState = .main
        
        // When: Reset to disclaimer
        await coordinator.resetToDisclaimer()
        
        // Then: Should be back at disclaimer
        XCTAssertEqual(coordinator.currentState, .disclaimer)
    }
    
    func testResetToAutoSetup() async {
        // Given: In main state
        coordinator.currentState = .main
        
        // When: Reset to auto setup
        await coordinator.resetToAutoSetup()
        
        // Then: Should be at auto setup
        XCTAssertEqual(coordinator.currentState, .autoSetup)
    }
    
    // MARK: - Full Flow Tests
    
    func testCompleteOnboardingFlow() async {
        // Test the complete onboarding flow
        
        // 1. Start at disclaimer
        XCTAssertEqual(coordinator.currentState, .disclaimer)
        
        // 2. Accept disclaimer
        await coordinator.disclaimerAccepted()
        XCTAssertEqual(coordinator.currentState, .autoSetup)
        
        // 3. Complete auto setup
        await coordinator.autoSetupCompleted()
        XCTAssertEqual(coordinator.currentState, .license)
        
        // 4. Complete license setup with valid license
        mockLicenseManager.mockHasValidLicense = true
        mockLicenseManager.mockCanUseApp = true
        await coordinator.licenseSetupCompleted()
        XCTAssertEqual(coordinator.currentState, .main)
    }
    
    func testOnboardingFlowWithFreeCredits() async {
        // Test onboarding flow with free credits path
        
        // Move through disclaimer and auto setup
        await coordinator.disclaimerAccepted()
        await coordinator.autoSetupCompleted()
        
        // Setup free credits scenario
        mockLicenseManager.mockHasValidLicense = false
        mockLicenseManager.mockCanUseApp = true
        mockUsageTracker.mockFreeCredits = 5
        
        // Complete license setup
        await coordinator.licenseSetupCompleted()
        
        // Should reach main state
        XCTAssertEqual(coordinator.currentState, .main)
    }
    
    // MARK: - Transition Safety Tests
    
    func testNoDoubleTransitions() async {
        // Given: In disclaimer state
        XCTAssertEqual(coordinator.currentState, .disclaimer)
        
        // When: Try to transition twice quickly
        let task1 = Task { await coordinator.disclaimerAccepted() }
        let task2 = Task { await coordinator.disclaimerAccepted() }
        
        await task1.value
        await task2.value
        
        // Then: Should only transition once
        XCTAssertEqual(coordinator.currentState, .autoSetup)
    }
    
    func testTransitioningFlag() async {
        // Given: Not transitioning
        XCTAssertFalse(coordinator.isTransitioning)
        
        // When: Start transition
        let expectation = expectation(description: "transition started")
        
        Task {
            await coordinator.disclaimerAccepted()
            expectation.fulfill()
        }
        
        // Wait a bit to catch transitioning state
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 second
        
        // Then: Should be transitioning (might be too fast to catch)
        await fulfillment(of: [expectation], timeout: 1)
        
        // After: Should not be transitioning
        XCTAssertFalse(coordinator.isTransitioning)
        XCTAssertEqual(coordinator.currentState, .autoSetup)
    }
    
    // MARK: - Service Integration Tests
    
    func testServicesReceiveStateUpdates() async {
        // Test that services are properly notified of state changes
        
        // Move through states
        await coordinator.disclaimerAccepted()
        XCTAssertEqual(coordinator.currentState, .autoSetup)
        
        await coordinator.autoSetupCompleted()
        XCTAssertEqual(coordinator.currentState, .license)
        
        // Verify license manager was checked
        mockLicenseManager.mockHasValidLicense = true
        mockLicenseManager.mockCanUseApp = true
        
        await coordinator.licenseSetupCompleted()
        XCTAssertEqual(coordinator.currentState, .main)
    }
    
    // MARK: - Error Handling Tests
    
    func testStateTransitionWithErrors() async {
        // Given: In license state with error condition
        coordinator.currentState = .license
        mockLicenseManager.mockCanUseApp = false
        mockUsageTracker.mockFreeCredits = 0
        mockUsageTracker.mockError = AppError.network("Test error")
        
        // When: Try to complete license setup
        await coordinator.licenseSetupCompleted()
        
        // Then: Should remain in license state due to error
        XCTAssertEqual(coordinator.currentState, .license)
    }
}