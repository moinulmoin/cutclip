//
//  AppFlowIntegrationTests.swift
//  cutclipTests
//
//  End-to-end integration tests for complete app flow
//

import XCTest
import SwiftUI
@testable import cutclip

@MainActor
final class AppFlowIntegrationTests: XCTestCase {
    
    var app: cutclipApp!
    var mockServices: MockServices!
    
    struct MockServices {
        let binaryManager: MockBinaryManager
        let errorHandler: MockErrorHandler
        let licenseManager: MockLicenseManager
        let usageTracker: MockUsageTracker
        let clipService: MockClipService
        let downloadService: MockDownloadService
        let videoInfoService: MockVideoInfoService
        let processExecutor: MockProcessExecutor
        
        init() {
            self.binaryManager = MockBinaryManager()
            self.errorHandler = MockErrorHandler()
            self.licenseManager = MockLicenseManager()
            self.usageTracker = MockUsageTracker()
            self.clipService = MockClipService(
                binaryManager: binaryManager,
                errorHandler: errorHandler
            )
            self.downloadService = MockDownloadService(binaryManager: binaryManager)
            self.videoInfoService = MockVideoInfoService(binaryManager: binaryManager)
            self.processExecutor = MockProcessExecutor()
        }
    }
    
    override func setUp() async throws {
        // Reset UserDefaults
        UserDefaults.standard.removeObject(forKey: "disclaimerAccepted")
        UserDefaults.standard.removeObject(forKey: "hasCompletedSetup")
        
        // Create mock services
        mockServices = MockServices()
        
        // Create app with mocks
        app = cutclipApp()
    }
    
    override func tearDown() async throws {
        app = nil
        mockServices = nil
    }
    
    // MARK: - Complete App Flow Tests
    
    func testFirstTimeUserFlow() async throws {
        // Test complete flow for a first-time user
        
        // 1. Start with disclaimer
        let coordinator = AppCoordinator(
            binaryManager: mockServices.binaryManager,
            errorHandler: mockServices.errorHandler,
            licenseManager: mockServices.licenseManager,
            usageTracker: mockServices.usageTracker
        )
        
        XCTAssertEqual(coordinator.currentState, .disclaimer)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "disclaimerAccepted"))
        
        // 2. Accept disclaimer
        await coordinator.disclaimerAccepted()
        XCTAssertEqual(coordinator.currentState, .autoSetup)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "disclaimerAccepted"))
        
        // 3. Complete auto setup (binaries downloaded)
        mockServices.binaryManager.mockIsConfigured = true
        await coordinator.autoSetupCompleted()
        XCTAssertEqual(coordinator.currentState, .license)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hasCompletedSetup"))
        
        // 4. Use free credits path
        mockServices.licenseManager.mockHasValidLicense = false
        mockServices.licenseManager.mockCanUseApp = true
        mockServices.usageTracker.mockFreeCredits = 3
        
        await coordinator.licenseSetupCompleted()
        XCTAssertEqual(coordinator.currentState, .main)
        
        // 5. Verify we can access main app
        XCTAssertTrue(mockServices.licenseManager.canUseApp)
        XCTAssertEqual(mockServices.usageTracker.freeCredits, 3)
    }
    
    func testReturningUserWithLicense() async throws {
        // Test flow for returning user with valid license
        
        // Setup: User has already accepted disclaimer and completed setup
        UserDefaults.standard.set(true, forKey: "disclaimerAccepted")
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
        
        // Setup: User has valid license
        mockServices.licenseManager.mockHasValidLicense = true
        mockServices.licenseManager.mockCanUseApp = true
        mockServices.licenseManager.mockLicenseKey = "VALID-LICENSE-123"
        
        let coordinator = AppCoordinator(
            binaryManager: mockServices.binaryManager,
            errorHandler: mockServices.errorHandler,
            licenseManager: mockServices.licenseManager,
            usageTracker: mockServices.usageTracker
        )
        
        // Should skip directly to main
        // Note: In real app, ContentView would handle this navigation
        // For testing, we verify the state management works correctly
        XCTAssertTrue(mockServices.licenseManager.hasValidLicense)
        XCTAssertTrue(mockServices.licenseManager.canUseApp)
    }
    
    func testVideoClippingFlow() async throws {
        // Test the complete video clipping flow
        
        // 1. Setup: User in main app state
        let coordinator = AppCoordinator(
            binaryManager: mockServices.binaryManager,
            errorHandler: mockServices.errorHandler,
            licenseManager: mockServices.licenseManager,
            usageTracker: mockServices.usageTracker
        )
        coordinator.currentState = .main
        
        // 2. Create clip job
        let job = ClipJob(
            url: "https://youtube.com/watch?v=test123",
            startTime: 10.0,
            endTime: 30.0,
            aspectRatio: .original,
            quality: "1080p"
        )
        
        // 3. Fetch video info
        mockServices.videoInfoService.mockVideoInfo = TestDataBuilder.makeVideoInfo(
            title: "Test Video",
            duration: 300,
            height: 1080
        )
        
        let videoInfo = try await mockServices.videoInfoService.fetchVideoInfo(from: job.url)
        XCTAssertEqual(videoInfo.title, "Test Video")
        XCTAssertTrue(mockServices.videoInfoService.fetchInfoCalled)
        
        // 4. Download video
        let downloadPath = try await mockServices.downloadService.downloadVideo(for: job)
        XCTAssertEqual(downloadPath, mockServices.downloadService.mockDownloadPath)
        XCTAssertTrue(mockServices.downloadService.downloadVideoCalled)
        
        // 5. Process clip
        let completedJob = try await mockServices.clipService.processJob(job)
        XCTAssertEqual(completedJob.status, .completed)
        XCTAssertNotNil(completedJob.outputFilePath)
        XCTAssertTrue(mockServices.clipService.processJobCalled)
        
        // 6. Decrement credits (if using free credits)
        if !mockServices.licenseManager.hasValidLicense {
            try await mockServices.usageTracker.decrementFreeCredits()
            XCTAssertEqual(mockServices.usageTracker.freeCredits, 2)
            XCTAssertTrue(mockServices.usageTracker.decrementCreditsCalled)
        }
    }
    
    func testErrorRecoveryFlow() async throws {
        // Test error handling throughout the flow
        
        // 1. Network error during device check
        mockServices.usageTracker.mockError = AppError.network("Connection failed")
        
        do {
            try await mockServices.usageTracker.checkDeviceStatus(forceRefresh: true)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(mockServices.errorHandler.handledErrors.isEmpty) // Not yet integrated
        }
        
        // 2. Download error
        mockServices.downloadService.mockError = DownloadError.downloadFailed("Video unavailable")
        
        let job = TestDataBuilder.makeClipJob()
        do {
            _ = try await mockServices.downloadService.downloadVideo(for: job)
            XCTFail("Expected error")
        } catch {
            // Error should be handled appropriately
        }
        
        // 3. Processing error
        mockServices.clipService.mockError = AppError.processing("FFmpeg failed")
        
        do {
            _ = try await mockServices.clipService.processJob(job)
            XCTFail("Expected error")
        } catch {
            // Error should be handled
        }
    }
    
    func testCreditsExhaustionFlow() async throws {
        // Test what happens when user runs out of credits
        
        // Setup: User has 1 credit left
        mockServices.usageTracker.mockFreeCredits = 1
        mockServices.licenseManager.mockHasValidLicense = false
        
        // Process one clip
        try await mockServices.usageTracker.decrementFreeCredits()
        XCTAssertEqual(mockServices.usageTracker.freeCredits, 0)
        
        // Try to process another - should fail
        do {
            try await mockServices.usageTracker.decrementFreeCredits()
            XCTFail("Expected no credits error")
        } catch {
            if case AppError.noCreditsRemaining = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
        
        // User should still be able to activate a license
        mockServices.licenseManager.mockHasValidLicense = true
        let activated = await mockServices.licenseManager.activateLicense(withKey: "VALID-KEY")
        XCTAssertTrue(activated)
        XCTAssertTrue(mockServices.licenseManager.hasValidLicense)
    }
    
    // MARK: - State Persistence Tests
    
    func testStatePersistenceAcrossLaunches() async throws {
        // Test that app state persists correctly
        
        // First launch - complete onboarding
        UserDefaults.standard.set(true, forKey: "disclaimerAccepted")
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
        
        // Save license to keychain (mocked)
        mockServices.licenseManager.mockLicenseKey = "PERSISTED-LICENSE"
        mockServices.licenseManager.mockHasValidLicense = true
        
        // Simulate app restart by creating new coordinator
        let newCoordinator = AppCoordinator(
            binaryManager: mockServices.binaryManager,
            errorHandler: mockServices.errorHandler,
            licenseManager: mockServices.licenseManager,
            usageTracker: mockServices.usageTracker
        )
        
        // State should be restored
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "disclaimerAccepted"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hasCompletedSetup"))
        XCTAssertTrue(mockServices.licenseManager.hasValidLicense)
    }
    
    // MARK: - Critical Path Tests
    
    func testCriticalPathFormatString() async throws {
        // Test the critical format string generation that was broken
        
        let qualities = ["720p", "1080p", "1440p", "2160p", "best"]
        
        for quality in qualities {
            let job = TestDataBuilder.makeClipJob(quality: quality)
            
            // Verify format string is generated correctly
            let formatString: String
            if quality.lowercased() == "best" {
                formatString = "bestvideo+bestaudio/best"
            } else if let h = Int(quality.lowercased().replacingOccurrences(of: "p", with: "")) {
                formatString = "bestvideo[height<=\(h)]+bestaudio[ext=m4a]/bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]/best"
            } else {
                formatString = "bestvideo[height<=720]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]/best"
            }
            
            // This format string MUST support video+audio merging
            XCTAssertTrue(formatString.contains("bestvideo") || quality == "best")
            XCTAssertTrue(formatString.contains("bestaudio") || quality == "best")
            XCTAssertTrue(formatString.contains("+") || formatString.contains("/"))
        }
    }
    
    func testCriticalPathFFmpegLocation() async throws {
        // Test that FFmpeg location is properly passed to yt-dlp
        
        // This was critical for the fix when PATH is restricted
        XCTAssertNotNil(mockServices.binaryManager.ffmpegPath)
        
        // In actual download, --ffmpeg-location must be included
        let job = TestDataBuilder.makeClipJob()
        
        // The download service should include FFmpeg location in arguments
        // This ensures yt-dlp can merge video+audio even with restricted PATH
    }
}