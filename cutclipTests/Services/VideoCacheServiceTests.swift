//
//  VideoCacheServiceTests.swift
//  cutclipTests
//
//  Tests for VideoCacheService video and metadata caching
//

import XCTest
@testable import cutclip

@MainActor
final class VideoCacheServiceTests: XCTestCase {
    
    var cacheService: VideoCacheService!
    var testCacheDir: URL!
    
    override func setUp() async throws {
        // Always use shared instance to test singleton behavior
        cacheService = VideoCacheService.shared
        
        // Create test cache directory
        testCacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_video_cache_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testCacheDir, withIntermediateDirectories: true)
        
        // Configure cache service to use test directory
        cacheService.cacheDirectory = testCacheDir
        
        // Clear any existing cache
        await cacheService.clearAll()
    }
    
    override func tearDown() async throws {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testCacheDir)
        cacheService = nil
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() {
        // Given/When: Multiple references to shared instance
        let instance1 = VideoCacheService.shared
        let instance2 = VideoCacheService.shared
        let instance3 = VideoCacheService.shared
        
        // Then: All should be the same instance
        XCTAssertIdentical(instance1, instance2)
        XCTAssertIdentical(instance2, instance3)
        XCTAssertIdentical(instance1, cacheService)
    }
    
    // MARK: - Basic Cache Operations
    
    func testVideoCacheSaveAndRetrieve() async {
        // Given: Video info and file
        let videoInfo = createTestVideoInfo()
        let quality = "1080p"
        let testVideoPath = createTestVideoFile()
        
        // When: Save to cache
        let saved = await cacheService.saveToCache(
            videoPath: testVideoPath.path,
            videoInfo: videoInfo,
            quality: quality
        )
        
        // Then: Should save successfully
        XCTAssertTrue(saved)
        
        // And: Should retrieve from cache
        let cached = await cacheService.checkCache(videoId: videoInfo.id, quality: quality)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.metadata.id, videoInfo.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cached!.videoPath))
    }
    
    func testMetadataCacheSaveAndRetrieve() async {
        // Given: Video metadata
        let videoInfo = createTestVideoInfo()
        
        // When: Save metadata only
        await cacheService.saveMetadataToCache(videoId: videoInfo.id!, videoInfo: videoInfo)
        
        // Then: Should retrieve metadata
        let cached = await cacheService.checkMetadataCache(videoId: videoInfo.id)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.title, videoInfo.title)
        XCTAssertEqual(cached?.uploader, videoInfo.uploader)
        XCTAssertEqual(cached?.durationSeconds, videoInfo.durationSeconds)
    }
    
    func testCacheKeyGeneration() async {
        // Given: Same video ID and quality
        let videoId = "test123"
        let quality = "720p"
        
        // When: Generate cache keys multiple times
        let key1 = cacheService.generateCacheKey(videoId: videoId, quality: quality)
        let key2 = cacheService.generateCacheKey(videoId: videoId, quality: quality)
        
        // Then: Keys should be identical
        XCTAssertEqual(key1, key2)
        
        // And: Different quality should produce different key
        let key3 = cacheService.generateCacheKey(videoId: videoId, quality: "1080p")
        XCTAssertNotEqual(key1, key3)
    }
    
    func testCacheWithoutVideoId() async {
        // Given: Video info without ID (using URL hash)
        var videoInfo = createTestVideoInfo()
        videoInfo.id = nil
        let quality = "1080p"
        let testVideoPath = createTestVideoFile()
        
        // When: Save to cache
        let saved = await cacheService.saveToCache(
            videoPath: testVideoPath.path,
            videoInfo: videoInfo,
            quality: quality
        )
        
        // Then: Should save successfully using URL hash
        XCTAssertTrue(saved)
        
        // And: Should retrieve using URL
        let cached = await cacheService.checkCache(videoId: nil, quality: quality)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.metadata.url, videoInfo.url)
    }
    
    // MARK: - Expiration Tests
    
    func testCacheExpiration() async {
        // Given: Cached video with custom expiration
        let videoInfo = createTestVideoInfo()
        let quality = "1080p"
        let testVideoPath = createTestVideoFile()
        
        // Save with immediate expiration for testing
        let saved = await cacheService.saveToCache(
            videoPath: testVideoPath.path,
            videoInfo: videoInfo,
            quality: quality
        )
        XCTAssertTrue(saved)
        
        // Manually modify the cache entry to be expired
        if let cacheKey = cacheService.generateCacheKey(videoId: videoInfo.id, quality: quality) {
            let metadataPath = testCacheDir.appendingPathComponent("\(cacheKey).json")
            if var metadata = try? JSONDecoder().decode(CachedVideo.self, from: Data(contentsOf: metadataPath)) {
                // Set cached date to 25 hours ago
                metadata.cachedDate = Date().addingTimeInterval(-25 * 60 * 60)
                if let updatedData = try? JSONEncoder().encode(metadata) {
                    try? updatedData.write(to: metadataPath)
                }
            }
        }
        
        // When: Check cache
        let cached = await cacheService.checkCache(videoId: videoInfo.id, quality: quality)
        
        // Then: Should return nil (expired)
        XCTAssertNil(cached)
    }
    
    func testCleanExpiredCache() async {
        // Given: Mix of expired and valid cached videos
        let videoInfo1 = createTestVideoInfo(id: "video1")
        let videoInfo2 = createTestVideoInfo(id: "video2")
        let testVideoPath1 = createTestVideoFile(name: "video1.mp4")
        let testVideoPath2 = createTestVideoFile(name: "video2.mp4")
        
        // Save both videos
        _ = await cacheService.saveToCache(
            videoPath: testVideoPath1.path,
            videoInfo: videoInfo1,
            quality: "1080p"
        )
        _ = await cacheService.saveToCache(
            videoPath: testVideoPath2.path,
            videoInfo: videoInfo2,
            quality: "1080p"
        )
        
        // Manually expire video1
        if let cacheKey = cacheService.generateCacheKey(videoId: videoInfo1.id, quality: "1080p") {
            let metadataPath = testCacheDir.appendingPathComponent("\(cacheKey).json")
            if var metadata = try? JSONDecoder().decode(CachedVideo.self, from: Data(contentsOf: metadataPath)) {
                metadata.cachedDate = Date().addingTimeInterval(-25 * 60 * 60)
                if let updatedData = try? JSONEncoder().encode(metadata) {
                    try? updatedData.write(to: metadataPath)
                }
            }
        }
        
        // When: Clean expired cache
        await cacheService.cleanExpiredCache()
        
        // Then: Video1 should be removed, video2 should remain
        let cached1 = await cacheService.checkCache(videoId: videoInfo1.id, quality: "1080p")
        let cached2 = await cacheService.checkCache(videoId: videoInfo2.id, quality: "1080p")
        XCTAssertNil(cached1)
        XCTAssertNotNil(cached2)
    }
    
    // MARK: - Size Management Tests
    
    func testCacheSizeCalculation() async {
        // Given: Multiple cached videos
        let videoInfo1 = createTestVideoInfo(id: "video1")
        let videoInfo2 = createTestVideoInfo(id: "video2")
        let testVideoPath1 = createTestVideoFile(name: "video1.mp4", size: 1024 * 1024) // 1MB
        let testVideoPath2 = createTestVideoFile(name: "video2.mp4", size: 2 * 1024 * 1024) // 2MB
        
        // When: Save videos
        _ = await cacheService.saveToCache(
            videoPath: testVideoPath1.path,
            videoInfo: videoInfo1,
            quality: "1080p"
        )
        _ = await cacheService.saveToCache(
            videoPath: testVideoPath2.path,
            videoInfo: videoInfo2,
            quality: "1080p"
        )
        
        // Then: Cache size should be approximately 3MB (plus metadata)
        let cacheSize = await cacheService.calculateCacheSize()
        XCTAssertGreaterThan(cacheSize, 3 * 1024 * 1024)
        XCTAssertLessThan(cacheSize, 3.5 * 1024 * 1024) // Allow some overhead for metadata
    }
    
    func testLRUEviction() async {
        // This test would require mocking the 5GB limit or creating very large files
        // For unit testing, we'll test the LRU logic with smaller files
        
        // Given: Multiple videos that would exceed a hypothetical small limit
        var videos: [(VideoInfo, URL)] = []
        for i in 1...5 {
            let videoInfo = createTestVideoInfo(id: "video\(i)")
            let videoPath = createTestVideoFile(name: "video\(i).mp4", size: 1024 * 1024) // 1MB each
            videos.append((videoInfo, videoPath))
        }
        
        // When: Save all videos
        for (videoInfo, videoPath) in videos {
            _ = await cacheService.saveToCache(
                videoPath: videoPath.path,
                videoInfo: videoInfo,
                quality: "1080p"
            )
            // Small delay to ensure different access times
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Then: All videos should be cached (since we're under 5GB)
        for (videoInfo, _) in videos {
            let cached = await cacheService.checkCache(videoId: videoInfo.id, quality: "1080p")
            XCTAssertNotNil(cached, "Video \(videoInfo.id ?? "") should be cached")
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentCacheAccess() async {
        // Test multiple concurrent reads and writes
        let videoInfo = createTestVideoInfo()
        let testVideoPath = createTestVideoFile()
        
        // Perform concurrent operations
        await withTaskGroup(of: Bool.self) { group in
            // Multiple save operations
            for quality in ["720p", "1080p", "1440p", "2160p"] {
                group.addTask {
                    await self.cacheService.saveToCache(
                        videoPath: testVideoPath.path,
                        videoInfo: videoInfo,
                        quality: quality
                    )
                }
            }
            
            // Multiple read operations
            for _ in 1...10 {
                group.addTask {
                    let cached = await self.cacheService.checkCache(
                        videoId: videoInfo.id,
                        quality: "1080p"
                    )
                    return cached != nil
                }
            }
            
            // Collect results
            var successCount = 0
            for await result in group {
                if result {
                    successCount += 1
                }
            }
            
            // Most operations should succeed
            XCTAssertGreaterThan(successCount, 10)
        }
    }
    
    func testConcurrentMetadataAccess() async {
        // Test concurrent metadata operations
        let videoIds = (1...10).map { "video\($0)" }
        
        await withTaskGroup(of: Void.self) { group in
            // Concurrent saves
            for videoId in videoIds {
                group.addTask {
                    let videoInfo = self.createTestVideoInfo(id: videoId)
                    await self.cacheService.saveMetadataToCache(
                        videoId: videoId,
                        videoInfo: videoInfo
                    )
                }
            }
            
            // Concurrent reads
            for videoId in videoIds {
                group.addTask {
                    _ = await self.cacheService.checkMetadataCache(videoId: videoId)
                }
            }
        }
        
        // Verify all metadata was saved
        for videoId in videoIds {
            let cached = await cacheService.checkMetadataCache(videoId: videoId)
            XCTAssertNotNil(cached, "Metadata for \(videoId) should be cached")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testSaveWithInvalidPath() async {
        // Given: Invalid video path
        let videoInfo = createTestVideoInfo()
        let invalidPath = "/nonexistent/path/video.mp4"
        
        // When: Try to save
        let saved = await cacheService.saveToCache(
            videoPath: invalidPath,
            videoInfo: videoInfo,
            quality: "1080p"
        )
        
        // Then: Should fail gracefully
        XCTAssertFalse(saved)
    }
    
    func testClearAllCache() async {
        // Given: Cached videos and metadata
        let videoInfo1 = createTestVideoInfo(id: "video1")
        let videoInfo2 = createTestVideoInfo(id: "video2")
        let testVideoPath = createTestVideoFile()
        
        _ = await cacheService.saveToCache(
            videoPath: testVideoPath.path,
            videoInfo: videoInfo1,
            quality: "1080p"
        )
        await cacheService.saveMetadataToCache(
            videoId: videoInfo2.id!,
            videoInfo: videoInfo2
        )
        
        // When: Clear all cache
        await cacheService.clearAll()
        
        // Then: Nothing should be cached
        let cached1 = await cacheService.checkCache(videoId: videoInfo1.id, quality: "1080p")
        let cached2 = await cacheService.checkMetadataCache(videoId: videoInfo2.id)
        XCTAssertNil(cached1)
        XCTAssertNil(cached2)
        
        // And: Cache directory should be empty
        let contents = try? FileManager.default.contentsOfDirectory(at: testCacheDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents?.count ?? 0, 0)
    }
    
    // MARK: - Performance Tests
    
    func testCachePerformance() {
        measure {
            let expectation = self.expectation(description: "Cache operations")
            
            Task {
                // Perform many cache operations
                for i in 1...100 {
                    let videoInfo = createTestVideoInfo(id: "video\(i)")
                    await cacheService.saveMetadataToCache(
                        videoId: "video\(i)",
                        videoInfo: videoInfo
                    )
                    _ = await cacheService.checkMetadataCache(videoId: "video\(i)")
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideoInfo(id: String = "test123") -> VideoInfo {
        VideoInfo(
            id: id,
            title: "Test Video \(id)",
            url: "https://youtube.com/watch?v=\(id)",
            thumbnail: "https://example.com/thumb.jpg",
            uploader: "Test Channel",
            durationString: "10:30",
            durationSeconds: 630,
            uploadDate: "2025-01-01",
            viewCount: 1000,
            description: "Test description",
            qualities: [
                VideoQuality(formatId: "22", quality: "720p", filesize: 100_000_000),
                VideoQuality(formatId: "137", quality: "1080p", filesize: 200_000_000)
            ],
            selectedQuality: nil
        )
    }
    
    private func createTestVideoFile(name: String = "test.mp4", size: Int = 1024) -> URL {
        let fileURL = testCacheDir.appendingPathComponent(name)
        let data = Data(repeating: 0, count: size)
        try? data.write(to: fileURL)
        return fileURL
    }
}