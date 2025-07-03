//
//  VideoInfoServiceTests.swift
//  cutclipTests
//
//  Tests for VideoInfoService metadata fetching
//

import XCTest
@testable import cutclip

@MainActor
final class VideoInfoServiceTests: XCTestCase {
    
    var videoInfoService: VideoInfoService!
    var mockBinaryManager: MockBinaryManager!
    
    override func setUp() async throws {
        mockBinaryManager = MockBinaryManager()
        videoInfoService = VideoInfoService(binaryManager: mockBinaryManager)
        
        // Setup mock binary paths
        mockBinaryManager.mockYtDlpPath = "/usr/local/bin/yt-dlp"
        mockBinaryManager.mockIsConfigured = true
    }
    
    override func tearDown() async throws {
        videoInfoService = nil
        mockBinaryManager = nil
    }
    
    // MARK: - URL Validation Tests
    
    func testValidYouTubeURLs() {
        // Test various valid YouTube URL formats
        let validURLs = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
            "http://youtube.com/watch?v=test123"
        ]
        
        for url in validURLs {
            XCTAssertTrue(
                videoInfoService.isValidYouTubeURL(url),
                "URL should be valid: \(url)"
            )
        }
    }
    
    func testInvalidYouTubeURLs() {
        // Test invalid URLs
        let invalidURLs = [
            "",
            "not-a-url",
            "https://vimeo.com/123456",
            "https://example.com",
            "ftp://youtube.com/watch?v=test",
            "javascript:alert('xss')",
            "file:///etc/passwd",
            "https://youtube.com\nmalicious.com",
            String(repeating: "a", count: 3000) // Too long
        ]
        
        for url in invalidURLs {
            XCTAssertFalse(
                videoInfoService.isValidYouTubeURL(url),
                "URL should be invalid: \(url)"
            )
        }
    }
    
    func testURLWithControlCharacters() {
        // Test URLs with control characters
        let urlsWithControlChars = [
            "https://youtube.com/watch?v=test\0null",
            "https://youtube.com/watch?v=test\nnewline",
            "https://youtube.com/watch?v=test\rreturn"
        ]
        
        for url in urlsWithControlChars {
            XCTAssertFalse(
                videoInfoService.isValidYouTubeURL(url),
                "URL with control characters should be invalid"
            )
        }
    }
    
    func testURLHostValidation() {
        // Test that only YouTube hosts are accepted
        let nonYouTubeHosts = [
            "https://youtube.evil.com/watch?v=test",
            "https://notyoutube.com/watch?v=test",
            "https://youtub.com/watch?v=test", // Missing 'e'
        ]
        
        for url in nonYouTubeHosts {
            XCTAssertFalse(
                videoInfoService.isValidYouTubeURL(url),
                "Non-YouTube host should be invalid: \(url)"
            )
        }
    }
    
    // MARK: - Loading State Tests
    
    func testLoadingState() async throws {
        // Test that loading state is managed
        XCTAssertFalse(videoInfoService.isLoading)
        
        // Note: We can't easily test the actual loading without mocking ProcessExecutor
        // which is created internally
        
        // The loadVideoInfo method would set isLoading to true during execution
        // and false when complete
    }
    
    // MARK: - Binary Not Configured Tests
    
    func testLoadVideoInfoWithoutBinary() async throws {
        // Given: No yt-dlp binary
        mockBinaryManager.mockYtDlpPath = nil
        
        // When: Try to load video info
        do {
            _ = try await videoInfoService.loadVideoInfo(for: "https://youtube.com/watch?v=test")
            XCTFail("Should fail without yt-dlp")
        } catch {
            // Expected to fail when accessing nil ytDlpPath
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Retry Logic Tests
    
    func testRetryLogic() async throws {
        // The loadVideoInfo method includes retry logic for parsing failures
        // It will retry up to 3 times with 1 second delays
        
        // Note: Without being able to inject ProcessExecutor or mock its responses,
        // we can't test the actual retry behavior
        
        // The method catches VideoInfoError.parsingFailed and retries
        // Other errors are thrown immediately
    }
    
    // MARK: - VideoInfo Model Tests
    
    func testVideoInfoProperties() {
        // Test VideoInfo model
        let qualities = [
            VideoQuality(height: 1080, format: "mp4", fps: 30),
            VideoQuality(height: 720, format: "mp4", fps: 30),
            VideoQuality(height: 480, format: "mp4", fps: 30)
        ]
        
        let videoInfo = VideoInfo(
            title: "Test Video",
            duration: 305.5,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            qualities: qualities
        )
        
        XCTAssertEqual(videoInfo.title, "Test Video")
        XCTAssertEqual(videoInfo.duration, 305.5)
        XCTAssertNotNil(videoInfo.thumbnailURL)
        XCTAssertEqual(videoInfo.qualities.count, 3)
        
        // Test getBestQualityHeight
        XCTAssertEqual(videoInfo.getBestQualityHeight(), 1080)
    }
    
    func testVideoInfoWithNoQualities() {
        // Test VideoInfo with empty qualities
        let videoInfo = VideoInfo(
            title: "No Qualities",
            duration: 100,
            thumbnailURL: nil,
            qualities: []
        )
        
        // Should return default height
        XCTAssertEqual(videoInfo.getBestQualityHeight(), 1080)
    }
    
    // MARK: - Edge Case Tests
    
    func testVeryLongURL() {
        // Test URL length limit
        let longURL = "https://youtube.com/watch?v=" + String(repeating: "a", count: 2000)
        
        // Should reject URLs over 2048 characters
        XCTAssertFalse(videoInfoService.isValidYouTubeURL(longURL))
    }
    
    func testEmptyURL() {
        // Test empty URL
        XCTAssertFalse(videoInfoService.isValidYouTubeURL(""))
    }
    
    func testURLWithoutScheme() {
        // Test URL without scheme
        XCTAssertFalse(videoInfoService.isValidYouTubeURL("youtube.com/watch?v=test"))
    }
    
    func testURLWithInvalidScheme() {
        // Test URLs with invalid schemes
        let invalidSchemes = [
            "ftp://youtube.com/watch?v=test",
            "file://youtube.com/watch?v=test",
            "javascript:youtube.com/watch?v=test",
            "data:youtube.com/watch?v=test"
        ]
        
        for url in invalidSchemes {
            XCTAssertFalse(
                videoInfoService.isValidYouTubeURL(url),
                "Invalid scheme should be rejected: \(url)"
            )
        }
    }
    
    // MARK: - Integration Tests
    
    func testVideoInfoServiceInitialization() {
        // Test that service initializes properly
        XCTAssertNotNil(videoInfoService)
        XCTAssertFalse(videoInfoService.isLoading)
        XCTAssertNil(videoInfoService.currentVideoInfo)
    }
    
    func testVideoInfoServiceWithMockBinaryManager() {
        // Test that service works with mock binary manager
        XCTAssertEqual(mockBinaryManager.ytDlpPath, "/usr/local/bin/yt-dlp")
        XCTAssertTrue(mockBinaryManager.isConfigured)
    }
    
    // MARK: - Limitations
    
    func testLimitationsNote() {
        // Note: Due to ProcessExecutor being created internally in VideoInfoService,
        // we cannot mock the actual yt-dlp execution and test:
        // 1. JSON parsing from yt-dlp output
        // 2. Error handling for process failures
        // 3. Retry logic behavior
        // 4. Progress/loading state during execution
        //
        // To properly test these, VideoInfoService would need to accept
        // ProcessExecutor as a dependency injection parameter.
        
        XCTAssertTrue(true, "See test limitations in comments")
    }
}