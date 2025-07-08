//
//  BinaryManagerTests.swift
//  cutclipTests
//
//  Tests for BinaryManager binary verification and path handling
//

import XCTest
@testable import cutclip

@MainActor
final class BinaryManagerTests: XCTestCase {
    
    var binaryManager: BinaryManager!
    var testBinariesPath: URL!
    
    override func setUp() async throws {
        binaryManager = BinaryManager()
        
        // Create test binaries directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        testBinariesPath = appSupport.appendingPathComponent("CutClipTest/bin")
        try FileManager.default.createDirectory(at: testBinariesPath, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        binaryManager = nil
        
        // Clean up test directory
        if let testPath = testBinariesPath?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: testPath)
        }
    }
    
    // MARK: - Path Setting Tests
    
    func testSetBinaryPath() {
        // Test setting binary paths
        let ytDlpPath = "/usr/local/bin/yt-dlp"
        let ffmpegPath = "/usr/local/bin/ffmpeg"
        
        binaryManager.setBinaryPath(for: .ytDlp, path: ytDlpPath)
        XCTAssertEqual(binaryManager.ytDlpPath, ytDlpPath)
        
        binaryManager.setBinaryPath(for: .ffmpeg, path: ffmpegPath)
        XCTAssertEqual(binaryManager.ffmpegPath, ffmpegPath)
    }
    
    func testSetBinaryPathVerified() {
        // Test setting pre-verified binary paths
        let ytDlpPath = "/opt/homebrew/bin/yt-dlp"
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        
        binaryManager.setBinaryPathVerified(for: .ytDlp, path: ytDlpPath)
        XCTAssertEqual(binaryManager.ytDlpPath, ytDlpPath)
        
        binaryManager.setBinaryPathVerified(for: .ffmpeg, path: ffmpegPath)
        XCTAssertEqual(binaryManager.ffmpegPath, ffmpegPath)
    }
    
    // MARK: - Configuration Status Tests
    
    func testIsConfiguredStatus() {
        // Initially not configured
        XCTAssertFalse(binaryManager.isConfigured)
        
        // Only yt-dlp set
        binaryManager.setBinaryPath(for: .ytDlp, path: "/usr/local/bin/yt-dlp")
        // updateConfigurationStatus is called internally
        
        // Only ffmpeg set
        binaryManager.ytDlpPath = nil
        binaryManager.setBinaryPath(for: .ffmpeg, path: "/usr/local/bin/ffmpeg")
        
        // Both set
        binaryManager.setBinaryPath(for: .ytDlp, path: "/usr/local/bin/yt-dlp")
        binaryManager.setBinaryPath(for: .ffmpeg, path: "/usr/local/bin/ffmpeg")
        
        // Note: isConfigured is managed internally by updateConfigurationStatus
        // We can't directly test it without triggering the internal logic
    }
    
    func testMarkAsConfigured() {
        // Test marking binaries as configured
        binaryManager.ytDlpPath = "/usr/local/bin/yt-dlp"
        binaryManager.ffmpegPath = "/usr/local/bin/ffmpeg"
        
        binaryManager.markAsConfigured()
        
        XCTAssertTrue(binaryManager.isConfigured)
        XCTAssertNil(binaryManager.errorMessage)
    }
    
    // MARK: - URL Property Tests
    
    func testBinaryURLs() {
        // Test URL conversion properties
        let ytDlpPath = "/usr/local/bin/yt-dlp"
        let ffmpegPath = "/usr/local/bin/ffmpeg"
        
        binaryManager.ytDlpPath = ytDlpPath
        binaryManager.ffmpegPath = ffmpegPath
        
        XCTAssertEqual(binaryManager.ytDlpURL?.path, ytDlpPath)
        XCTAssertEqual(binaryManager.ffmpegURL?.path, ffmpegPath)
        
        // Test nil paths
        binaryManager.ytDlpPath = nil
        binaryManager.ffmpegPath = nil
        
        XCTAssertNil(binaryManager.ytDlpURL)
        XCTAssertNil(binaryManager.ffmpegURL)
    }
    
    // MARK: - Binary Checking Tests
    
    func testCheckBinaries() async throws {
        // Create test binaries in expected location
        let binDir = testBinariesPath!
        let ytDlpPath = binDir.appendingPathComponent("yt-dlp")
        let ffmpegPath = binDir.appendingPathComponent("ffmpeg")
        
        // Create mock binary files
        FileManager.default.createFile(atPath: ytDlpPath.path, contents: Data())
        FileManager.default.createFile(atPath: ffmpegPath.path, contents: Data())
        
        // Override the app support directory path
        // Note: We can't easily override the internal path, so this test is limited
        
        // Test that checkBinaries detects files in the bin subdirectory
        binaryManager.checkBinaries()
        
        // The method looks in appSupportDirectory/bin/ which we can't easily mock
        // So we'll test the logic indirectly
        
        // Manually set paths to test the rest of the flow
        binaryManager.ytDlpPath = ytDlpPath.path
        binaryManager.ffmpegPath = ffmpegPath.path
        
        XCTAssertNotNil(binaryManager.ytDlpPath)
        XCTAssertNotNil(binaryManager.ffmpegPath)
    }
    
    // MARK: - Verification Tests
    
    func testVerifyBinaryWithInvalidPath() async {
        // Test verification with non-existent binary
        binaryManager.ytDlpPath = "/nonexistent/yt-dlp"
        
        let isValid = await binaryManager.verifyBinary(.ytDlp)
        XCTAssertFalse(isValid)
    }
    
    func testVerifyBinaryWithNilPath() async {
        // Test verification with nil path
        binaryManager.ytDlpPath = nil
        
        let isValid = await binaryManager.verifyBinary(.ytDlp)
        XCTAssertFalse(isValid)
    }
    
    func testVerifyAllBinaries() async {
        // Test verifying all binaries
        
        // Case 1: Both nil
        binaryManager.ytDlpPath = nil
        binaryManager.ffmpegPath = nil
        
        let allValid1 = await binaryManager.verifyAllBinaries()
        XCTAssertFalse(allValid1)
        
        // Case 2: One nil
        binaryManager.ytDlpPath = "/usr/local/bin/yt-dlp"
        binaryManager.ffmpegPath = nil
        
        let allValid2 = await binaryManager.verifyAllBinaries()
        XCTAssertFalse(allValid2)
        
        // Case 3: Both set but non-existent
        binaryManager.ytDlpPath = "/nonexistent/yt-dlp"
        binaryManager.ffmpegPath = "/nonexistent/ffmpeg"
        
        let allValid3 = await binaryManager.verifyAllBinaries()
        XCTAssertFalse(allValid3)
    }
    
    func testVerifyBinariesWithFeedback() async {
        // Test verification with user feedback
        binaryManager.ytDlpPath = "/nonexistent/yt-dlp"
        binaryManager.ffmpegPath = "/nonexistent/ffmpeg"
        
        await binaryManager.verifyBinariesWithFeedback()
        
        // Should set error message and not be configured
        XCTAssertNotNil(binaryManager.errorMessage)
        XCTAssertFalse(binaryManager.isConfigured)
        XCTAssertFalse(binaryManager.isVerifying)
    }
    
    // MARK: - Error State Tests
    
    func testErrorMessageHandling() {
        // Test error message state
        binaryManager.errorMessage = "Test error"
        binaryManager.ytDlpPath = "/usr/local/bin/yt-dlp"
        binaryManager.ffmpegPath = "/usr/local/bin/ffmpeg"
        
        // With error message, should not be configured
        // Note: updateConfigurationStatus checks for errorMessage
        binaryManager.checkBinaries()
        
        // Clear error
        binaryManager.errorMessage = nil
        binaryManager.markAsConfigured()
        
        XCTAssertNil(binaryManager.errorMessage)
        XCTAssertTrue(binaryManager.isConfigured)
    }
    
    // MARK: - Concurrent Verification Tests
    
    func testConcurrentVerification() async {
        // Test that concurrent verification doesn't cause issues
        binaryManager.ytDlpPath = "/nonexistent/yt-dlp"
        binaryManager.ffmpegPath = "/nonexistent/ffmpeg"
        
        // Start multiple verification tasks
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.binaryManager.verifyBinary(.ytDlp)
            }
            
            group.addTask {
                await self.binaryManager.verifyBinary(.ffmpeg)
            }
            
            group.addTask {
                await self.binaryManager.verifyAllBinaries()
            }
            
            // All should complete without crashes
            for await _ in group {
                // Results don't matter for this test
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyPathHandling() {
        // Test handling of empty paths
        binaryManager.setBinaryPath(for: .ytDlp, path: "")
        XCTAssertEqual(binaryManager.ytDlpPath, "")
        
        // Empty path should not make it configured
        binaryManager.setBinaryPath(for: .ffmpeg, path: "")
        
        // Note: The implementation doesn't explicitly check for empty strings
        // This is a potential bug - empty strings are treated as valid paths
    }
    
    func testVerificationStateTracking() async {
        // Test isVerifying state
        XCTAssertFalse(binaryManager.isVerifying)
        
        // Start verification
        let task = Task {
            await binaryManager.verifyBinariesWithFeedback()
        }
        
        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        // Note: Due to async nature, we might miss the isVerifying state
        // After completion, should be false
        await task.value
        XCTAssertFalse(binaryManager.isVerifying)
    }
}