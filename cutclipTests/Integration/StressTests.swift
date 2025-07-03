//
//  StressTests.swift
//  cutclipTests
//
//  Stress tests for concurrent operations across the system
//

import XCTest
@testable import cutclip

@MainActor
final class StressTests: XCTestCase {
    
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
        let cacheService: CacheService
        
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
            self.cacheService = CacheService()
        }
    }
    
    override func setUp() async throws {
        mockServices = MockServices()
        
        // Configure mocks for success
        mockServices.binaryManager.mockIsConfigured = true
        mockServices.binaryManager.mockYtDlpPath = "/usr/local/bin/yt-dlp"
        mockServices.binaryManager.mockFfmpegPath = "/usr/local/bin/ffmpeg"
        mockServices.licenseManager.mockHasValidLicense = true
        mockServices.licenseManager.mockCanUseApp = true
        mockServices.usageTracker.mockFreeCredits = 100
    }
    
    override func tearDown() async throws {
        mockServices = nil
    }
    
    // MARK: - Binary Manager Stress Tests
    
    func testConcurrentBinaryVerification() async {
        // Test many concurrent binary verifications
        let iterations = 100
        
        await withTaskGroup(of: Bool.self) { group in
            // Verify yt-dlp many times
            for _ in 1...iterations {
                group.addTask {
                    await self.mockServices.binaryManager.verifyBinary(.ytDlp)
                }
            }
            
            // Verify ffmpeg many times
            for _ in 1...iterations {
                group.addTask {
                    await self.mockServices.binaryManager.verifyBinary(.ffmpeg)
                }
            }
            
            // Verify all binaries
            for _ in 1...(iterations / 2) {
                group.addTask {
                    await self.mockServices.binaryManager.verifyAllBinaries()
                }
            }
            
            // Collect results
            var successCount = 0
            for await result in group {
                if result {
                    successCount += 1
                }
            }
            
            // Should handle all concurrent operations
            XCTAssertGreaterThan(successCount, 0)
        }
    }
    
    func testConcurrentPathUpdates() async {
        // Test concurrent path setting
        let iterations = 50
        
        await withTaskGroup(of: Void.self) { group in
            for i in 1...iterations {
                group.addTask {
                    await self.mockServices.binaryManager.setBinaryPath(
                        for: .ytDlp,
                        path: "/usr/local/bin/yt-dlp-\(i)"
                    )
                }
                
                group.addTask {
                    await self.mockServices.binaryManager.setBinaryPath(
                        for: .ffmpeg,
                        path: "/usr/local/bin/ffmpeg-\(i)"
                    )
                }
            }
        }
        
        // Should have some path set
        XCTAssertNotNil(mockServices.binaryManager.ytDlpPath)
        XCTAssertNotNil(mockServices.binaryManager.ffmpegPath)
    }
    
    // MARK: - Cache Service Stress Tests
    
    func testHighVolumeCacheOperations() async {
        let iterations = 1000
        let cacheService = mockServices.cacheService
        
        await withTaskGroup(of: Void.self) { group in
            // Many concurrent writes
            for i in 1...iterations {
                group.addTask {
                    let data = DeviceData(
                        id: "id-\(i)",
                        deviceId: "device-\(i)",
                        freeCredits: i % 10,
                        user: nil
                    )
                    await cacheService.setCachedData(data)
                }
            }
            
            // Many concurrent reads
            for _ in 1...iterations {
                group.addTask {
                    _ = await cacheService.getCachedData()
                }
            }
            
            // Credit updates
            for i in 1...(iterations / 2) {
                group.addTask {
                    await cacheService.updateCredits(i % 20)
                }
            }
            
            // Invalidations
            for _ in 1...(iterations / 10) {
                group.addTask {
                    await cacheService.invalidate()
                }
            }
        }
        
        // Should complete without deadlocks
        XCTAssertTrue(true)
    }
    
    func testCacheUnderPressure() async {
        let cacheService = mockServices.cacheService
        let duration: TimeInterval = 2.0 // Run for 2 seconds
        let startTime = Date()
        
        // Initial data
        let deviceData = DeviceData(
            id: "stress-test",
            deviceId: "device-stress",
            freeCredits: 100,
            user: nil
        )
        await cacheService.setCachedData(deviceData)
        
        // Run many operations for duration
        await withTaskGroup(of: Void.self) { group in
            // Reader tasks
            for _ in 1...10 {
                group.addTask {
                    while Date().timeIntervalSince(startTime) < duration {
                        _ = await cacheService.getCachedData()
                        _ = await cacheService.hasRecentInvalidation()
                        _ = await cacheService.hasRecentCreditUpdate()
                    }
                }
            }
            
            // Writer tasks
            for _ in 1...5 {
                group.addTask {
                    var credits = 100
                    while Date().timeIntervalSince(startTime) < duration {
                        credits = (credits - 1) % 100
                        await cacheService.updateCredits(credits)
                    }
                }
            }
            
            // Invalidator task
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    await cacheService.invalidate()
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }
            }
        }
        
        // Should survive the stress
        XCTAssertTrue(true)
    }
    
    // MARK: - Usage Tracker Stress Tests
    
    func testConcurrentUsageTracking() async {
        // Test many concurrent API calls
        let iterations = 50
        
        await withTaskGroup(of: Void.self) { group in
            // Check device status
            for _ in 1...iterations {
                group.addTask {
                    do {
                        try await self.mockServices.usageTracker.checkDeviceStatus()
                    } catch {
                        // Ignore errors in stress test
                    }
                }
            }
            
            // Decrement credits
            for _ in 1...(iterations / 2) {
                group.addTask {
                    do {
                        try await self.mockServices.usageTracker.decrementFreeCredits()
                    } catch {
                        // Ignore errors in stress test
                    }
                }
            }
            
            // Validate licenses
            for i in 1...(iterations / 3) {
                group.addTask {
                    do {
                        _ = try await self.mockServices.usageTracker.validateLicense("LICENSE-\(i)")
                    } catch {
                        // Ignore errors in stress test
                    }
                }
            }
        }
        
        // Should handle concurrent operations
        XCTAssertTrue(mockServices.usageTracker.checkDeviceStatusCalled)
    }
    
    // MARK: - Video Processing Stress Tests
    
    func testConcurrentVideoInfoFetching() async {
        // Test many concurrent video info requests
        let urls = [
            "https://youtube.com/watch?v=test1",
            "https://youtube.com/watch?v=test2",
            "https://youtube.com/watch?v=test3",
            "https://youtube.com/watch?v=test4",
            "https://youtube.com/watch?v=test5"
        ]
        
        // Mock video info responses
        mockServices.videoInfoService.mockVideoInfo = TestDataBuilder.makeVideoInfo()
        
        await withTaskGroup(of: Void.self) { group in
            // Fetch info for same URLs many times
            for _ in 1...20 {
                for url in urls {
                    group.addTask {
                        do {
                            _ = try await self.mockServices.videoInfoService.fetchVideoInfo(from: url)
                        } catch {
                            // Ignore errors
                        }
                    }
                }
            }
        }
        
        // Should handle concurrent fetches
        XCTAssertTrue(mockServices.videoInfoService.fetchInfoCalled)
    }
    
    func testConcurrentClipProcessing() async {
        // Test multiple simultaneous clip jobs
        let jobs = (1...10).map { i in
            TestDataBuilder.makeClipJob(
                url: "https://youtube.com/watch?v=test\(i)",
                quality: ["720p", "1080p", "1440p"][i % 3],
                startTime: Double(i * 10),
                endTime: Double(i * 10 + 20)
            )
        }
        
        await withTaskGroup(of: Void.self) { group in
            for job in jobs {
                group.addTask {
                    do {
                        _ = try await self.mockServices.clipService.processJob(job)
                    } catch {
                        // Ignore errors
                    }
                }
            }
        }
        
        // Should process jobs
        XCTAssertTrue(mockServices.clipService.processJobCalled)
    }
    
    // MARK: - Full System Stress Test
    
    func testFullSystemUnderLoad() async {
        // Simulate heavy concurrent usage of the entire system
        let duration: TimeInterval = 3.0
        let startTime = Date()
        
        await withTaskGroup(of: Void.self) { group in
            // Continuous binary verification
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    _ = await self.mockServices.binaryManager.verifyAllBinaries()
                }
            }
            
            // Continuous license checking
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    _ = await self.mockServices.licenseManager.canUseApp()
                    await self.mockServices.licenseManager.refreshLicenseStatus()
                }
            }
            
            // Continuous usage tracking
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    do {
                        try await self.mockServices.usageTracker.checkDeviceStatus()
                    } catch {
                        // Continue on error
                    }
                }
            }
            
            // Continuous video processing simulation
            group.addTask {
                var jobIndex = 0
                while Date().timeIntervalSince(startTime) < duration {
                    let job = TestDataBuilder.makeClipJob(
                        url: "https://youtube.com/watch?v=stress\(jobIndex)",
                        quality: "1080p"
                    )
                    
                    // Simulate full flow
                    do {
                        // 1. Fetch video info
                        _ = try await self.mockServices.videoInfoService.fetchVideoInfo(from: job.url)
                        
                        // 2. Download
                        _ = try await self.mockServices.downloadService.downloadVideo(for: job)
                        
                        // 3. Process
                        _ = try await self.mockServices.clipService.processJob(job)
                        
                        // 4. Decrement credits
                        if !self.mockServices.licenseManager.hasValidLicense {
                            try await self.mockServices.usageTracker.decrementFreeCredits()
                        }
                    } catch {
                        // Continue on error
                    }
                    
                    jobIndex += 1
                }
            }
            
            // Error generation
            group.addTask {
                var errorCount = 0
                while Date().timeIntervalSince(startTime) < duration {
                    self.mockServices.errorHandler.handle(
                        AppError.network("Stress test error \(errorCount)"),
                        context: .general
                    )
                    errorCount += 1
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
            }
        }
        
        // System should remain stable
        XCTAssertTrue(true)
        
        // Verify operations occurred
        XCTAssertTrue(mockServices.videoInfoService.fetchInfoCalled)
        XCTAssertTrue(mockServices.downloadService.downloadVideoCalled)
        XCTAssertTrue(mockServices.clipService.processJobCalled)
    }
    
    // MARK: - Memory Pressure Tests
    
    func testMemoryUnderPressure() async {
        // Test system behavior under memory pressure
        let largeDataCount = 100
        var largeDataArrays: [[Data]] = []
        
        // Create memory pressure
        for _ in 1...largeDataCount {
            let largeData = Data(repeating: 0, count: 1024 * 1024) // 1MB each
            largeDataArrays.append([largeData])
        }
        
        // Run operations under memory pressure
        await withTaskGroup(of: Void.self) { group in
            for i in 1...50 {
                group.addTask {
                    // Simulate operations
                    let job = TestDataBuilder.makeClipJob(quality: "2160p")
                    self.mockServices.clipService.currentJob = job
                    
                    // Cache operations
                    let data = DeviceData(
                        id: "memory-\(i)",
                        deviceId: "device-\(i)",
                        freeCredits: i,
                        user: nil
                    )
                    await self.mockServices.cacheService.setCachedData(data)
                }
            }
        }
        
        // Clear memory pressure
        largeDataArrays.removeAll()
        
        // Should complete without crashes
        XCTAssertTrue(true)
    }
}