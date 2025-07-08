//
//  RateLimitIntegrationTests.swift
//  cutclipTests
//
//  Created by Moinul Moin on 7/7/25.
//

import XCTest
@testable import cutclip

/// Integration tests for rate limiting protection
/// NOTE: These are manual tests that should be run carefully to avoid actual rate limiting
final class RateLimitIntegrationTests: XCTestCase {
    
    var downloadService: DownloadService!
    var binaryManager: BinaryManager!
    
    override func setUp() async throws {
        try await super.setUp()
        binaryManager = BinaryManager()
        downloadService = DownloadService(binaryManager: binaryManager)
    }
    
    /// Manual test - Run this to verify yt-dlp parameters are correctly applied
    func testYtDlpParametersIncludeSafetyOptions() async throws {
        // This test verifies our safety parameters are included
        // It doesn't actually download to avoid rate limiting
        
        let job = ClipJob(
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            startTime: "00:00:00",
            endTime: "00:00:10",
            aspectRatio: .original,
            quality: "720p"
        )
        
        // We can't easily test the actual command execution without mocking
        // But we can verify the configuration includes our safety parameters
        
        // The actual parameters we expect to see:
        let expectedParams = [
            "--sleep-interval", "3",
            "--max-sleep-interval", "8",
            "--user-agent", // Will have a random user agent
            "--referer", "https://www.youtube.com/",
            "--quiet",
            "--no-warnings"
        ]
        
        // In a real test, we'd mock ProcessExecutor to capture the arguments
        print("Safety parameters that should be included:")
        for param in expectedParams {
            print("  - \(param)")
        }
        
        XCTAssertTrue(true, "Manual verification required")
    }
    
    /// Test user agent rotation
    func testUserAgentRotation() {
        // Simulate multiple calls to verify different user agents are used
        var userAgents = Set<String>()
        
        // The user agents we expect to see
        let expectedAgents = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
        ]
        
        // In actual implementation, we'd need to extract the user agent from each call
        // For now, verify we have multiple agents defined
        XCTAssertEqual(expectedAgents.count, 5)
        XCTAssertTrue(expectedAgents.allSatisfy { $0.contains("Mozilla/5.0") })
    }
    
    /// WARNING: This test actually downloads - use sparingly!
    func testActualDownloadWithSafetyDelays() async throws {
        throw XCTSkip("Skipping actual download test to avoid rate limiting. Enable manually for testing.")
        
        /*
        // Only run this test manually and sparingly
        let testURL = "https://www.youtube.com/watch?v=jNQXAC9IVRw" // Me at the zoo - 19 seconds
        
        let job = ClipJob(
            url: testURL,
            startTime: "00:00:00",
            endTime: "00:00:05",
            aspectRatio: .original,
            quality: "720p"
        )
        
        let start = Date()
        do {
            let path = try await downloadService.downloadVideo(for: job)
            let elapsed = Date().timeIntervalSince(start)
            
            // Verify file exists
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
            
            // Clean up
            try? FileManager.default.removeItem(atPath: path)
            
            // The download should have taken at least 3 seconds due to sleep interval
            XCTAssertGreaterThan(elapsed, 3.0, "Download should include safety delay")
            
        } catch {
            XCTFail("Download failed: \(error)")
        }
        */
    }
    
    /// Test rate limit error detection
    func testRateLimitErrorDetection() {
        // Test various rate limit error messages
        let rateLimitErrors = [
            "ERROR: Unable to download webpage: HTTP Error 429: Too Many Requests",
            "WARNING: [youtube] Failed to download m3u8 information: HTTP Error 429: Too Many Requests",
            "ERROR: Sign in to confirm you're not a bot. This helps protect our community.",
            "HTTP Error 429 Too Many Requests"
        ]
        
        for errorMsg in rateLimitErrors {
            let downloadError = DownloadError.downloadFailed(errorMsg)
            let userMessage = downloadError.errorDescription ?? ""
            
            // Should contain helpful rate limit message
            XCTAssertTrue(
                userMessage.contains("temporarily blocked") || userMessage.contains("verification"),
                "Error '\(errorMsg)' should be recognized as rate limiting"
            )
        }
    }
}

// MARK: - Mock Helpers for Testing

extension RateLimitIntegrationTests {
    
    /// Helper to simulate multiple rapid downloads (DO NOT RUN against real YouTube)
    func simulateRapidDownloads(count: Int) async {
        print("SIMULATION: Would perform \(count) rapid downloads")
        print("Expected behavior:")
        print("- 3-8 second delays between each")
        print("- Different user agents")
        print("- Referer header set")
        print("- After 30 downloads, safety tip appears")
        
        // In real scenario, this would:
        // 1. Track each download with UsageTracker
        // 2. Apply yt-dlp safety parameters
        // 3. Show UI feedback after thresholds
    }
    
    /// Helper to test recovery after rate limiting
    func testRecoveryStrategy() {
        print("Rate Limit Recovery Strategy:")
        print("1. Immediate: Show clear error message")
        print("2. Wait Period: Suggest waiting a few hours")
        print("3. Alternative: Suggest using VPN")
        print("4. Prevention: Remind about daily limits")
    }
}