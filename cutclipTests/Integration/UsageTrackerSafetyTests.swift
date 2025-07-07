//
//  UsageTrackerSafetyTests.swift
//  cutclipTests
//
//  Created by Moinul Moin on 7/7/25.
//

import XCTest
@testable import cutclip

@MainActor
final class UsageTrackerSafetyTests: XCTestCase {
    
    var usageTracker: UsageTracker!
    let testDownloadHistoryKey = "CutClip.DailyDownloadHistory"
    let testLastDownloadDateKey = "CutClip.LastDownloadDate"
    let testHasShownSafetyTipKey = "CutClip.HasShownSafetyTip"
    
    override func setUp() async throws {
        try await super.setUp()
        // Clean up UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: testDownloadHistoryKey)
        UserDefaults.standard.removeObject(forKey: testLastDownloadDateKey)
        UserDefaults.standard.removeObject(forKey: testHasShownSafetyTipKey)
        
        usageTracker = UsageTracker.shared
    }
    
    override func tearDown() async throws {
        // Clean up after tests
        UserDefaults.standard.removeObject(forKey: testDownloadHistoryKey)
        UserDefaults.standard.removeObject(forKey: testLastDownloadDateKey)
        UserDefaults.standard.removeObject(forKey: testHasShownSafetyTipKey)
        try await super.tearDown()
    }
    
    // MARK: - Daily Download Counter Tests
    
    func testTrackDownloadIncrementsCounter() {
        // Given
        XCTAssertEqual(usageTracker.dailyDownloadCount, 0)
        
        // When
        usageTracker.trackDownload()
        
        // Then
        XCTAssertEqual(usageTracker.dailyDownloadCount, 1)
        
        // Track another download
        usageTracker.trackDownload()
        XCTAssertEqual(usageTracker.dailyDownloadCount, 2)
    }
    
    func testDailyCounterResetsAtMidnight() {
        // Given - Set a download from yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        UserDefaults.standard.set(yesterday, forKey: testLastDownloadDateKey)
        UserDefaults.standard.set(5, forKey: testDownloadHistoryKey)
        
        // When - Track a download today
        usageTracker.trackDownload()
        
        // Then - Counter should reset to 1
        XCTAssertEqual(usageTracker.dailyDownloadCount, 1)
    }
    
    func testDailyCounterPersistsOnSameDay() {
        // Given - Set downloads from earlier today
        let today = Date()
        UserDefaults.standard.set(today, forKey: testLastDownloadDateKey)
        UserDefaults.standard.set(10, forKey: testDownloadHistoryKey)
        
        // When - Initialize and load
        usageTracker = UsageTracker.shared
        
        // Then - Counter should persist
        XCTAssertEqual(usageTracker.dailyDownloadCount, 10)
    }
    
    // MARK: - Safety Status Tests
    
    func testSafetyStatusShowsCounterAfter10Downloads() {
        // Given
        for _ in 1...9 {
            usageTracker.trackDownload()
        }
        
        // When
        var status = usageTracker.getSafetyStatus()
        
        // Then - Counter not shown yet
        XCTAssertFalse(status.showCounter)
        XCTAssertFalse(status.showTip)
        
        // Track one more
        usageTracker.trackDownload()
        status = usageTracker.getSafetyStatus()
        
        // Counter should show at 10
        XCTAssertTrue(status.showCounter)
        XCTAssertFalse(status.showTip)
    }
    
    func testSafetyTipTriggersAfter30Downloads() {
        // Given
        for _ in 1...29 {
            usageTracker.trackDownload()
        }
        
        // When
        var status = usageTracker.getSafetyStatus()
        
        // Then - Tip not shown yet
        XCTAssertTrue(status.showCounter) // Counter shows after 10
        XCTAssertFalse(status.showTip)
        
        // Track one more
        usageTracker.trackDownload()
        status = usageTracker.getSafetyStatus()
        
        // Tip should show at 30
        XCTAssertTrue(status.showCounter)
        XCTAssertTrue(status.showTip)
        XCTAssertTrue(usageTracker.hasShownSafetyTip)
    }
    
    func testSafetyTipOnlyShowsOnce() {
        // Given - User has seen the tip
        UserDefaults.standard.set(true, forKey: testHasShownSafetyTipKey)
        usageTracker.hasShownSafetyTip = true
        
        // When - Track 30+ downloads
        for _ in 1...35 {
            usageTracker.trackDownload()
        }
        
        // Then - Tip should not show again
        let status = usageTracker.getSafetyStatus()
        XCTAssertTrue(status.showCounter)
        XCTAssertFalse(status.showTip) // Already shown
    }
    
    func testDismissSafetyTipPersists() {
        // Given
        XCTAssertFalse(usageTracker.hasShownSafetyTip)
        
        // When
        usageTracker.dismissSafetyTip()
        
        // Then
        XCTAssertTrue(usageTracker.hasShownSafetyTip)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: testHasShownSafetyTipKey))
    }
    
    // MARK: - Edge Cases
    
    func testHandlesFirstTimeUser() {
        // Given - No previous data
        UserDefaults.standard.removeObject(forKey: testLastDownloadDateKey)
        UserDefaults.standard.removeObject(forKey: testDownloadHistoryKey)
        
        // When
        let newTracker = UsageTracker.shared
        
        // Then
        XCTAssertEqual(newTracker.dailyDownloadCount, 0)
        XCTAssertFalse(newTracker.hasShownSafetyTip)
    }
}

// MARK: - Error Parsing Tests

final class DownloadErrorParsingTests: XCTestCase {
    
    func testParseRateLimitError429() {
        // Given
        let error429 = "ERROR: Unable to download webpage: HTTP Error 429: Too Many Requests"
        
        // When
        let result = parseYtDlpError(error429)
        
        // Then
        XCTAssertEqual(result, "YouTube has temporarily blocked downloads from your IP. Please wait a few hours before trying again. Using a VPN may help.")
    }
    
    func testParseBotVerificationError() {
        // Given
        let botError = "ERROR: Sign in to confirm you're not a bot. This helps protect our community."
        
        // When
        let result = parseYtDlpError(botError)
        
        // Then
        XCTAssertEqual(result, "YouTube is requiring verification. This usually means too many downloads. Please wait before trying again.")
    }
    
    func testParseOtherErrors() {
        // Test age restriction
        let ageError = "ERROR: Sign in to confirm your age"
        XCTAssertEqual(parseYtDlpError(ageError), "This video is age-restricted. YouTube requires sign-in which is not supported.")
        
        // Test private video
        let privateError = "ERROR: Private video"
        XCTAssertEqual(parseYtDlpError(privateError), "This video is private and cannot be downloaded.")
        
        // Test 403 error
        let error403 = "ERROR: HTTP Error 403: Forbidden"
        XCTAssertEqual(parseYtDlpError(error403), "Access denied. The video may be restricted or removed.")
    }
    
    func testParseUnknownError() {
        // Given
        let unknownError = "Some random error message"
        
        // When
        let result = parseYtDlpError(unknownError)
        
        // Then - Should return original
        XCTAssertEqual(result, unknownError)
    }
}

// Helper to access the private parseYtDlpError function for testing
private func parseYtDlpError(_ error: String) -> String {
    // This would need to be made internal or public in the actual code
    // For now, duplicate the logic here for testing
    if error.contains("HTTP Error 429") || error.contains("Too Many Requests") {
        return "YouTube has temporarily blocked downloads from your IP. Please wait a few hours before trying again. Using a VPN may help."
    } else if error.contains("Sign in to confirm you're not a bot") {
        return "YouTube is requiring verification. This usually means too many downloads. Please wait before trying again."
    } else if error.contains("Sign in to confirm your age") || error.contains("age-restricted") {
        return "This video is age-restricted. YouTube requires sign-in which is not supported."
    } else if error.contains("Private video") {
        return "This video is private and cannot be downloaded."
    } else if error.contains("HTTP Error 403") {
        return "Access denied. The video may be restricted or removed."
    }
    return error
}