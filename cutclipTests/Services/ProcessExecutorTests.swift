//
//  ProcessExecutorTests.swift
//  cutclipTests
//
//  Tests for ProcessExecutor functionality
//

import XCTest
@testable import cutclip

final class ProcessExecutorTests: XCTestCase {
    
    var executor: ProcessExecutor!
    
    override func setUp() async throws {
        executor = ProcessExecutor()
    }
    
    override func tearDown() async throws {
        executor = nil
    }
    
    // MARK: - Basic Execution Tests
    
    func testSimpleCommandExecution() async throws {
        // Given: A simple echo command
        let config = ProcessConfiguration(
            executablePath: "/bin/echo",
            arguments: ["Hello, World!"]
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Should succeed with correct output
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.outputString?.trimmingCharacters(in: .whitespacesAndNewlines), "Hello, World!")
    }
    
    func testCommandWithError() async throws {
        // Given: A command that writes to stderr
        let config = ProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo 'Error message' >&2; exit 1"]
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Should capture error output
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.errorString?.trimmingCharacters(in: .whitespacesAndNewlines), "Error message")
    }
    
    // MARK: - Combined Output Tests
    
    func testCombinedOutputMode() async throws {
        // Given: Command with combined output mode (critical for yt-dlp)
        let config = ProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo 'stdout'; echo 'stderr' >&2"],
            combinedOutput: true
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Both outputs should be in the output (not error)
        XCTAssertTrue(result.isSuccess)
        let output = result.outputString ?? ""
        XCTAssertTrue(output.contains("stdout"))
        XCTAssertTrue(output.contains("stderr"))
        
        // Error should also have the combined output
        let error = result.errorString ?? ""
        XCTAssertTrue(error.contains("stdout"))
        XCTAssertTrue(error.contains("stderr"))
    }
    
    func testSeparateOutputMode() async throws {
        // Given: Command with separate output mode (default)
        let config = ProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo 'stdout'; echo 'stderr' >&2"],
            combinedOutput: false
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Outputs should be separate
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.outputString?.trimmingCharacters(in: .whitespacesAndNewlines), "stdout")
        XCTAssertEqual(result.errorString?.trimmingCharacters(in: .whitespacesAndNewlines), "stderr")
    }
    
    // MARK: - Progress Handler Tests
    
    func testOutputHandler() async throws {
        // Given: Command with output handler
        var capturedOutput = ""
        let config = ProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["-c", "for i in 1 2 3; do echo \"Line $i\"; sleep 0.1; done"],
            outputHandler: { output in
                capturedOutput += output
            }
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Handler should receive output
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(capturedOutput.contains("Line 1"))
        XCTAssertTrue(capturedOutput.contains("Line 2"))
        XCTAssertTrue(capturedOutput.contains("Line 3"))
    }
    
    // MARK: - Timeout Tests
    
    func testProcessTimeout() async {
        // Given: Command that takes too long
        let config = ProcessConfiguration(
            executablePath: "/bin/sleep",
            arguments: ["10"],
            timeout: 0.5 // 0.5 second timeout
        )
        
        // When/Then: Should throw timeout error
        do {
            _ = try await executor.execute(config)
            XCTFail("Expected timeout error")
        } catch let error as ProcessExecutorError {
            if case .timeout(let duration) = error {
                XCTAssertEqual(duration, 0.5)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Environment Tests
    
    func testRestrictedEnvironment() async throws {
        // Given: Command with restricted environment
        let config = ProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo $PATH"],
            environment: ["PATH": "/usr/bin:/bin"]
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Should have restricted PATH
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.outputString?.trimmingCharacters(in: .whitespacesAndNewlines), "/usr/bin:/bin")
    }
    
    // MARK: - Progress Parsing Tests
    
    func testFFmpegProgressParsing() {
        // Test FFmpeg progress parsing
        var totalDuration: Double? = nil
        
        // Parse duration
        let durationOutput = "Duration: 00:05:30.50, start: 0.000000, bitrate: 1000 kb/s"
        let progress1 = ProcessExecutor.parseFFmpegProgress(
            from: durationOutput,
            totalDuration: &totalDuration
        )
        
        XCTAssertNil(progress1) // No progress yet, just duration
        XCTAssertEqual(totalDuration, 330.5) // 5:30.50 in seconds
        
        // Parse progress
        let progressOutput = "frame=  120 fps=30.0 q=28.0 size=    1024kB time=00:01:30.00 bitrate= 100.0kbits/s"
        let progress2 = ProcessExecutor.parseFFmpegProgress(
            from: progressOutput,
            totalDuration: &totalDuration
        )
        
        XCTAssertNotNil(progress2)
        XCTAssertEqual(progress2, 90.0 / 330.5, accuracy: 0.01) // 1:30 / 5:30.50
    }
    
    func testYtDlpProgressParsing() {
        // Test yt-dlp progress parsing
        
        let progressOutput = "[download]  45.5% of 15.30MiB at 2.50MiB/s ETA 00:03"
        let progress = ProcessExecutor.parseYtDlpProgress(from: progressOutput)
        
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress, 45.5)
    }
    
    // MARK: - Error Handling Tests
    
    func testLaunchFailure() async {
        // Given: Non-existent executable
        let config = ProcessConfiguration(
            executablePath: "/nonexistent/binary",
            arguments: []
        )
        
        // When/Then: Should throw launch failed error
        do {
            _ = try await executor.execute(config)
            XCTFail("Expected launch failure")
        } catch let error as ProcessExecutorError {
            if case .launchFailed = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Integration Tests
    
    func testSimulatedYtDlpExecution() async throws {
        // Simulate yt-dlp-like behavior with combined output
        let script = """
        echo '[youtube] Extracting video information'
        echo '[download] Downloading video' >&2
        echo '[download]   0.0% of 10.00MiB at Unknown speed ETA Unknown'
        sleep 0.1
        echo '[download]  50.0% of 10.00MiB at 5.00MiB/s ETA 00:01'
        sleep 0.1
        echo '[download] 100.0% of 10.00MiB at 5.00MiB/s ETA 00:00'
        echo '[ffmpeg] Merging formats into output.mp4' >&2
        """
        
        var progressUpdates: [Double] = []
        
        let config = ProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["-c", script],
            combinedOutput: true,
            outputHandler: { output in
                if let progress = ProcessExecutor.parseYtDlpProgress(from: output) {
                    progressUpdates.append(progress)
                }
            }
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Should capture all output and progress
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(progressUpdates, [0.0, 50.0, 100.0])
        
        let output = result.outputString ?? ""
        XCTAssertTrue(output.contains("Extracting video information"))
        XCTAssertTrue(output.contains("Downloading video"))
        XCTAssertTrue(output.contains("Merging formats"))
    }
    
    func testSimulatedFFmpegExecution() async throws {
        // Simulate FFmpeg-like behavior
        let script = """
        echo 'Input #0, mov,mp4,m4a,3gp,3g2,mj2, from input.mp4:' >&2
        echo '  Duration: 00:02:00.00, start: 0.000000, bitrate: 1000 kb/s' >&2
        echo 'Output #0, mp4, to output.mp4:' >&2
        sleep 0.1
        echo 'frame=  100 fps=25 q=-1.0 size=     512kB time=00:00:30.00 bitrate= 139.8kbits/s' >&2
        sleep 0.1
        echo 'frame=  200 fps=25 q=-1.0 size=    1024kB time=00:01:00.00 bitrate= 139.8kbits/s' >&2
        """
        
        var progressUpdates: [Double] = []
        var totalDuration: Double? = nil
        
        let config = ProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["-c", script],
            errorHandler: { error in
                if let progress = ProcessExecutor.parseFFmpegProgress(
                    from: error,
                    totalDuration: &totalDuration
                ) {
                    progressUpdates.append(progress)
                }
            }
        )
        
        // When: Execute
        let result = try await executor.execute(config)
        
        // Then: Should parse duration and progress
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(totalDuration, 120.0) // 2:00 in seconds
        XCTAssertEqual(progressUpdates.count, 2)
        XCTAssertEqual(progressUpdates[0], 0.25, accuracy: 0.01) // 30s / 120s
        XCTAssertEqual(progressUpdates[1], 0.50, accuracy: 0.01) // 60s / 120s
    }
}