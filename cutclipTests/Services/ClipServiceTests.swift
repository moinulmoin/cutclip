//
//  ClipServiceTests.swift
//  cutclipTests
//
//  Tests for ClipService video processing logic
//

import XCTest
@testable import cutclip

@MainActor
final class ClipServiceTests: XCTestCase {
    
    var clipService: ClipService!
    var mockBinaryManager: MockBinaryManager!
    var mockErrorHandler: MockErrorHandler!
    
    override func setUp() async throws {
        mockBinaryManager = MockBinaryManager()
        mockErrorHandler = MockErrorHandler()
        
        clipService = ClipService(
            binaryManager: mockBinaryManager
        )
        
        // Setup mock binaries
        mockBinaryManager.mockYtDlpPath = "/usr/local/bin/yt-dlp"
        mockBinaryManager.mockFfmpegPath = "/usr/local/bin/ffmpeg"
        mockBinaryManager.mockIsConfigured = true
    }
    
    override func tearDown() async throws {
        clipService = nil
        mockBinaryManager = nil
        mockErrorHandler = nil
        
        // Clean up any temp files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CutClip")
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Input Validation Tests
    
    func testInputValidation() async throws {
        // Test various invalid inputs
        let invalidPaths = [
            "",                              // Empty path
            String(repeating: "a", count: 3000), // Too long
            "/path/with\0null",             // Null byte
            "/path/with\nnewline",          // Newline
            "/path/with\rreturn"            // Carriage return
        ]
        
        for invalidPath in invalidPaths {
            let job = TestDataBuilder.makeClipJob()
            
            do {
                _ = try await clipService.clipVideo(inputPath: invalidPath, job: job)
                XCTFail("Should reject invalid path: \(invalidPath)")
            } catch ClipError.invalidInput(_) {
                // Expected
            } catch {
                XCTFail("Wrong error type for path: \(invalidPath)")
            }
        }
    }
    
    func testNonExistentFileHandling() async throws {
        // Given: Non-existent file
        let job = TestDataBuilder.makeClipJob()
        
        // When: Try to clip
        do {
            _ = try await clipService.clipVideo(inputPath: "/nonexistent/file.mp4", job: job)
            XCTFail("Should fail for non-existent file")
        } catch ClipError.invalidInput(let message) {
            XCTAssertTrue(message.contains("does not exist"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testTimeValidation() async throws {
        // Create a valid input file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CutClip")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let inputFile = tempDir.appendingPathComponent("test.mp4")
        FileManager.default.createFile(atPath: inputFile.path, contents: Data())
        
        // Test invalid time formats
        let invalidJobs = [
            TestDataBuilder.makeClipJob(startTime: "invalid", endTime: "00:00:30"),
            TestDataBuilder.makeClipJob(startTime: "00:00:30", endTime: "00:00:10"), // End before start
            TestDataBuilder.makeClipJob(startTime: "1:2:3", endTime: "00:00:30"), // Wrong format
        ]
        
        for job in invalidJobs {
            do {
                _ = try await clipService.clipVideo(inputPath: inputFile.path, job: job)
                XCTFail("Should reject invalid times")
            } catch ClipError.invalidInput(_) {
                // Expected
            } catch {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Binary Configuration Tests
    
    func testBinaryNotConfigured() async throws {
        // Given: No FFmpeg binary
        mockBinaryManager.mockFfmpegPath = nil
        
        let job = TestDataBuilder.makeClipJob()
        
        // When: Try to clip
        do {
            _ = try await clipService.clipVideo(inputPath: "/tmp/test.mp4", job: job)
            XCTFail("Should fail without FFmpeg")
        } catch ClipError.binaryNotFound(_) {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Time Conversion Tests
    
    func testTimeConversion() {
        // Test time string to seconds conversion
        let testCases: [(time: String, expectedSeconds: Double?)] = [
            ("00:00:00", 0),
            ("00:00:30", 30),
            ("00:01:00", 60),
            ("01:00:00", 3600),
            ("01:30:45", 5445),
            ("invalid", nil),
            ("1:2:3", nil), // Wrong format
        ]
        
        for (time, expected) in testCases {
            let seconds = clipService.convertTimeToSeconds(time)
            if let expected = expected {
                XCTAssertEqual(seconds, expected, "Time conversion failed for: \(time)")
            } else {
                XCTAssertNil(seconds, "Should return nil for invalid time: \(time)")
            }
        }
    }
    
    func testTimeFormatValidation() {
        // Test time format validation
        let validTimes = ["00:00:00", "01:30:45", "23:59:59"]
        let invalidTimes = ["", "1:2:3", "invalid", "00:00", "25:00:00"]
        
        for time in validTimes {
            XCTAssertTrue(clipService.isValidTimeFormat(time), "Should be valid: \(time)")
        }
        
        for time in invalidTimes {
            XCTAssertFalse(clipService.isValidTimeFormat(time), "Should be invalid: \(time)")
        }
    }
    
    // MARK: - Progress Tracking Tests
    
    func testProgressUpdate() async throws {
        // Test that progress updates are applied to current job
        let job = TestDataBuilder.makeClipJob()
        clipService.currentJob = job
        
        // Update progress
        await clipService.updateJobProgress(0.5)
        
        // Verify progress was updated
        XCTAssertEqual(clipService.currentJob?.progress, 0.5)
        XCTAssertEqual(clipService.currentJob?.status, job.status) // Other fields unchanged
    }
    
    // MARK: - Output File Tests
    
    func testOutputFileNaming() {
        // Test output file name generation
        let job = TestDataBuilder.makeClipJob(
            startTime: "00:10:30",
            endTime: "00:20:45"
        )
        
        let outputName = clipService.generateOutputFileName(for: job)
        
        // Should contain time range with colons replaced
        XCTAssertTrue(outputName.contains("00-10-30_to_00-20-45"))
        XCTAssertTrue(outputName.hasSuffix(".mp4"))
        XCTAssertTrue(outputName.hasPrefix("CutClip_"))
    }
    
    func testOutputDirectory() {
        // Test that output directory is Downloads
        let outputDir = clipService.getOutputDirectory()
        
        XCTAssertTrue(outputDir.path.contains("Downloads"))
    }
    
    // MARK: - Aspect Ratio Tests
    
    func testAspectRatioFilters() {
        // Test that aspect ratios have correct crop filters
        let aspectRatios = ClipJob.AspectRatio.allCases
        
        for aspectRatio in aspectRatios {
            switch aspectRatio {
            case .original:
                XCTAssertNil(aspectRatio.cropFilter)
            case .vertical916:
                XCTAssertEqual(aspectRatio.cropFilter, "crop=ih*9/16:ih")
            case .square11:
                XCTAssertEqual(aspectRatio.cropFilter, "crop=min(iw\\,ih):min(iw\\,ih)")
            case .standard43:
                XCTAssertEqual(aspectRatio.cropFilter, "crop=ih*4/3:ih")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorConversion() {
        // Test ClipError to AppError conversion
        let clipErrors: [(ClipError, AppError)] = [
            (.binaryNotFound("test"), .binaryNotFound("Setup required. Please configure required tools in Settings.")),
            (.invalidTimeFormat, .invalidInput("Start and end times must be in HH:MM:SS format.")),
            (.endTimeBeforeStartTime, .invalidInput("End time must be after start time.")),
            (.outputFileNotFound, .fileSystem("Unable to save video. Please check your disk space.")),
        ]
        
        for (clipError, expectedAppError) in clipErrors {
            let appError = clipError.toAppError()
            XCTAssertEqual(appError.localizedDescription, expectedAppError.localizedDescription)
        }
    }
    
    // MARK: - Integration Tests
    
    func testSuccessfulClipFlow() async throws {
        // Test the successful flow (without actually executing FFmpeg)
        
        // Create valid input file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CutClip")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let inputFile = tempDir.appendingPathComponent("input.mp4")
        FileManager.default.createFile(atPath: inputFile.path, contents: Data())
        
        // Create valid job
        let job = TestDataBuilder.makeClipJob(
            startTime: "00:00:10",
            endTime: "00:00:30",
            quality: "1080p"
        )
        
        // Note: We can't actually test clipVideo without mocking ProcessExecutor
        // which is created internally. This is a limitation of the current design.
        
        // At least verify the input validation passes
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputFile.path))
        XCTAssertTrue(ValidationUtils.isValidTimeFormat(job.startTime))
        XCTAssertTrue(ValidationUtils.isValidTimeFormat(job.endTime))
        
        let startSeconds = ValidationUtils.timeStringToSeconds(job.startTime)
        let endSeconds = ValidationUtils.timeStringToSeconds(job.endTime)
        XCTAssertNotNil(startSeconds)
        XCTAssertNotNil(endSeconds)
        XCTAssertLessThan(startSeconds!, endSeconds!)
    }
}