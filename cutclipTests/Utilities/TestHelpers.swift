//
//  TestHelpers.swift
//  cutclipTests
//
//  Test utilities and helpers for CutClip tests
//

import XCTest
import Foundation
@testable import cutclip

// MARK: - Async Test Helpers

extension XCTestCase {
    /// Execute an async test with proper timeout handling
    func asyncTest(
        timeout: TimeInterval = 10,
        _ block: @escaping () async throws -> Void
    ) {
        let expectation = expectation(description: "async test")
        
        Task {
            do {
                try await block()
                expectation.fulfill()
            } catch {
                XCTFail("Async test failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: timeout)
    }
    
    /// Wait for a condition to become true
    func waitForCondition(
        timeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.1,
        condition: @escaping () -> Bool
    ) {
        let expectation = expectation(description: "condition")
        
        Task {
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < timeout {
                if condition() {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
            XCTFail("Condition not met within timeout")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: timeout + 1)
    }
}

// MARK: - Mock URL Session

class MockURLSession: URLSessionProtocol {
    var responses: [URL: (data: Data?, response: URLResponse?, error: Error?)] = [:]
    var requestCount = 0
    var lastRequest: URLRequest?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        lastRequest = request
        
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        
        if let mockResponse = responses[url] {
            if let error = mockResponse.error {
                throw error
            }
            
            let data = mockResponse.data ?? Data()
            let response = mockResponse.response ?? HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            
            return (data, response)
        }
        
        throw URLError(.fileDoesNotExist)
    }
    
    func addMockResponse(
        for url: URL,
        data: Data? = nil,
        statusCode: Int = 200,
        error: Error? = nil
    ) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
        responses[url] = (data: data, response: response, error: error)
    }
}

// MARK: - Mock File Manager

class MockFileManager {
    var files: [URL: Data] = [:]
    var directories: Set<URL> = []
    
    func createDirectory(at url: URL) throws {
        directories.insert(url)
    }
    
    func fileExists(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return files[url] != nil || directories.contains(url)
    }
    
    func write(_ data: Data, to url: URL) throws {
        files[url] = data
    }
    
    func contents(at url: URL) throws -> Data {
        guard let data = files[url] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }
}

// MARK: - Test Data Builders

struct TestDataBuilder {
    static func makeDeviceResponse(
        deviceId: String = "test-device-id",
        freeCredits: Int = 3,
        isActive: Bool = true
    ) -> Data {
        let json = """
        {
            "id": "\(deviceId)",
            "free_credits": \(freeCredits),
            "is_active": \(isActive),
            "created_at": "2025-01-01T00:00:00Z",
            "last_used_at": "2025-01-01T00:00:00Z"
        }
        """
        return json.data(using: .utf8)!
    }
    
    static func makeLicenseResponse(
        key: String = "TEST-LICENSE-KEY",
        isValid: Bool = true,
        email: String = "test@example.com"
    ) -> Data {
        let json = """
        {
            "license_key": "\(key)",
            "is_valid": \(isValid),
            "email": "\(email)",
            "created_at": "2025-01-01T00:00:00Z",
            "expires_at": null
        }
        """
        return json.data(using: .utf8)!
    }
    
    static func makeVideoInfo(
        title: String = "Test Video",
        duration: Int = 300,
        height: Int = 1080
    ) -> VideoInfo {
        VideoInfo(
            title: title,
            duration: TimeInterval(duration),
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            qualities: [
                VideoQuality(height: height, format: "mp4", fps: 30)
            ]
        )
    }
    
    static func makeClipJob(
        url: String = "https://youtube.com/watch?v=test",
        quality: String = "1080p",
        startTime: Double = 10.0,
        endTime: Double = 30.0
    ) -> ClipJob {
        ClipJob(
            url: url,
            startTime: startTime,
            endTime: endTime,
            aspectRatio: .original,
            quality: quality
        )
    }
}

// MARK: - Process Mock

class MockProcess {
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    var terminationHandler: ((Process) -> Void)?
    
    private(set) var terminationStatus: Int32 = 0
    private(set) var isRunning = false
    
    // Mock configuration
    var mockExitCode: Int32 = 0
    var mockOutput: String = ""
    var mockError: String = ""
    var shouldFailToLaunch = false
    var executionDelay: TimeInterval = 0
    
    func run() throws {
        if shouldFailToLaunch {
            throw NSError(domain: "MockProcess", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Mock process launch failed"
            ])
        }
        
        isRunning = true
        
        // Simulate process execution
        Task {
            if executionDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(executionDelay * 1_000_000_000))
            }
            
            // Write output
            if let pipe = standardOutput as? Pipe {
                let outputData = mockOutput.data(using: .utf8) ?? Data()
                pipe.fileHandleForWriting.write(outputData)
            }
            
            // Write error
            if let pipe = standardError as? Pipe {
                let errorData = mockError.data(using: .utf8) ?? Data()
                pipe.fileHandleForWriting.write(errorData)
            }
            
            // Terminate
            await MainActor.run {
                self.isRunning = false
                self.terminationStatus = self.mockExitCode
                self.terminationHandler?(self as! Process)
            }
        }
    }
    
    func terminate() {
        isRunning = false
        terminationStatus = -15 // SIGTERM
    }
}

// MARK: - Keychain Mock

class MockKeychain {
    private var storage: [String: Data] = [:]
    
    func save(_ data: Data, for key: String) throws {
        storage[key] = data
    }
    
    func load(for key: String) throws -> Data {
        guard let data = storage[key] else {
            throw KeychainError.itemNotFound
        }
        return data
    }
    
    func delete(for key: String) throws {
        storage.removeValue(forKey: key)
    }
    
    func clear() {
        storage.removeAll()
    }
}

enum KeychainError: Error {
    case itemNotFound
}

// MARK: - Time Control

class TimeController {
    private var currentTime = Date()
    
    func advance(by interval: TimeInterval) {
        currentTime.addTimeInterval(interval)
    }
    
    func now() -> Date {
        currentTime
    }
    
    func reset() {
        currentTime = Date()
    }
}

// MARK: - Expectation Helpers

extension XCTestCase {
    /// Create an inverted expectation (expects something NOT to happen)
    func invertedExpectation(description: String) -> XCTestExpectation {
        let exp = expectation(description: description)
        exp.isInverted = true
        return exp
    }
    
    /// Assert that an async operation throws a specific error
    func assertThrowsError<T, E: Error & Equatable>(
        _ expression: @autoclosure () async throws -> T,
        expectedError: E,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error \(expectedError) but no error was thrown", file: file, line: line)
        } catch let error as E {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Expected error \(expectedError) but got \(error)", file: file, line: line)
        }
    }
}

// MARK: - URL Protocol for Testing

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}