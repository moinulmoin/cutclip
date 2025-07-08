//
//  ProcessExecutor.swift
//  cutclip
//
//  Created by Moinul Moin on 6/30/25.
//

import Foundation

/// Configuration for process execution
struct ProcessConfiguration: Sendable {
    let executablePath: String
    let arguments: [String]
    var environment: [String: String]?
    var timeout: TimeInterval = 120 // Default 2 minutes
    var outputHandler: (@Sendable (String) -> Void)?
    var errorHandler: (@Sendable (String) -> Void)?
    var combinedOutput: Bool = false // When true, combine stdout and stderr into single pipe
    
    init(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 120,
        outputHandler: (@Sendable (String) -> Void)? = nil,
        errorHandler: (@Sendable (String) -> Void)? = nil,
        combinedOutput: Bool = false
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        // Use secure default environment if not provided
        self.environment = environment ?? [
            "PATH": "/usr/bin:/bin",
            "HOME": NSTemporaryDirectory()
        ]
        self.timeout = timeout
        self.outputHandler = outputHandler
        self.errorHandler = errorHandler
        self.combinedOutput = combinedOutput
    }
}

/// Result from process execution
struct ProcessResult {
    let exitCode: Int32
    let output: Data
    let error: Data
    let duration: TimeInterval
    
    var isSuccess: Bool {
        exitCode == 0
    }
    
    var outputString: String? {
        String(data: output, encoding: .utf8)
    }
    
    var errorString: String? {
        String(data: error, encoding: .utf8)
    }
}

/// Unified process executor that handles common patterns across all services
final class ProcessExecutor: Sendable {
    
    /// Execute a process with the given configuration
    func execute(_ config: ProcessConfiguration) async throws -> ProcessResult {
        let startTime = Date()
        let stateManager = ProcessStateManager()
        let outputBuffer = DataBuffer()
        let errorBuffer = DataBuffer()
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: config.executablePath)
            process.arguments = config.arguments
            process.environment = config.environment
            
            let outputPipe = Pipe()
            let errorPipe: Pipe?
            
            if config.combinedOutput {
                // Use single pipe for both stdout and stderr (like original Process code)
                process.standardOutput = outputPipe
                process.standardError = outputPipe
                errorPipe = nil
            } else {
                // Use separate pipes
                process.standardOutput = outputPipe
                errorPipe = Pipe()
                process.standardError = errorPipe
            }
            
            // Handle output streaming
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    Task {
                        await outputBuffer.appendData(data)
                        if config.combinedOutput {
                            // In combined mode, all output goes to both buffers
                            await errorBuffer.appendData(data)
                        }
                        if let outputHandler = config.outputHandler,
                           let output = String(data: data, encoding: .utf8) {
                            outputHandler(output)
                        }
                    }
                }
            }
            
            // Handle error streaming (only if not combined)
            if let errorPipe = errorPipe {
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        Task {
                            await errorBuffer.appendData(data)
                            if let errorHandler = config.errorHandler,
                               let error = String(data: data, encoding: .utf8) {
                                errorHandler(error)
                            } else if let outputHandler = config.outputHandler,
                                      let output = String(data: data, encoding: .utf8) {
                                // Some tools (like FFmpeg) write progress to stderr
                                outputHandler(output)
                            }
                        }
                    }
                }
            }
            
            // Process termination handler
            process.terminationHandler = { process in
                Task {
                    // Clean up pipe handlers
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe?.fileHandleForReading.readabilityHandler = nil
                    
                    // Small delay to ensure all data is flushed
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    
                    // Read any remaining data
                    if let tailData = try? outputPipe.fileHandleForReading.readToEnd(), !tailData.isEmpty {
                        await outputBuffer.appendData(tailData)
                        if config.combinedOutput {
                            await errorBuffer.appendData(tailData)
                        }
                    }
                    if let errorPipe = errorPipe,
                       let errorTailData = try? errorPipe.fileHandleForReading.readToEnd(), 
                       !errorTailData.isEmpty {
                        await errorBuffer.appendData(errorTailData)
                    }
                    
                    let didResume = await stateManager.markResumedAndCleanup {
                        if process.isRunning {
                            process.terminate()
                            // Force kill after 5 seconds if needed
                            Task {
                                try? await Task.sleep(nanoseconds: 5_000_000_000)
                                if process.isRunning {
                                    process.interrupt()
                                }
                            }
                        }
                    }
                    
                    if !didResume {
                        let outputData = await outputBuffer.data
                        let errorData = await errorBuffer.data
                        let duration = Date().timeIntervalSince(startTime)
                        
                        let result = ProcessResult(
                            exitCode: process.terminationStatus,
                            output: outputData,
                            error: errorData,
                            duration: duration
                        )
                        
                        continuation.resume(returning: result)
                    }
                }
            }
            
            // Timeout handler
            Task {
                try? await Task.sleep(nanoseconds: UInt64(config.timeout * 1_000_000_000))
                let didResume = await stateManager.markResumedAndCleanup {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe?.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning {
                        process.terminate()
                    }
                }
                if !didResume {
                    continuation.resume(throwing: ProcessExecutorError.timeout(config.timeout))
                }
            }
            
            // Launch the process
            do {
                try process.run()
            } catch {
                Task {
                    _ = await stateManager.markResumedAndCleanup {
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        errorPipe?.fileHandleForReading.readabilityHandler = nil
                    }
                    continuation.resume(throwing: ProcessExecutorError.launchFailed(error.localizedDescription))
                }
            }
        }
    }
    
    /// Execute a process and parse the result with a custom parser
    func execute<T>(_ config: ProcessConfiguration, parser: (ProcessResult) async throws -> T) async throws -> T {
        let result = try await execute(config)
        return try await parser(result)
    }
    
    /// Execute a simple process synchronously (for quick operations like --version checks)
    func executeSimple(_ config: ProcessConfiguration) async throws -> Bool {
        let result = try await execute(config)
        return result.isSuccess
    }
}

// MARK: - Common Progress Parsers

extension ProcessExecutor {
    
    /// Parse FFmpeg progress output
    /// - Parameters:
    ///   - output: The FFmpeg output string
    ///   - totalDuration: Reference to store total duration once found
    /// - Returns: Progress percentage (0.0 to 1.0) if found
    static func parseFFmpegProgress(from output: String, totalDuration: inout Double?) -> Double? {
        // First look for total duration if we don't have it
        if totalDuration == nil {
            let durationPattern = #"Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})"#
            if let regex = try? NSRegularExpression(pattern: durationPattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)) {
                let hoursRange = Range(match.range(at: 1), in: output)!
                let minutesRange = Range(match.range(at: 2), in: output)!
                let secondsRange = Range(match.range(at: 3), in: output)!
                
                let hours = Double(String(output[hoursRange])) ?? 0
                let minutes = Double(String(output[minutesRange])) ?? 0
                let seconds = Double(String(output[secondsRange])) ?? 0
                
                totalDuration = hours * 3600 + minutes * 60 + seconds
            }
        }
        
        // Parse current time progress
        if let duration = totalDuration {
            let timePattern = #"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})"#
            if let regex = try? NSRegularExpression(pattern: timePattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)) {
                let hoursRange = Range(match.range(at: 1), in: output)!
                let minutesRange = Range(match.range(at: 2), in: output)!
                let secondsRange = Range(match.range(at: 3), in: output)!
                
                let hours = Double(String(output[hoursRange])) ?? 0
                let minutes = Double(String(output[minutesRange])) ?? 0
                let seconds = Double(String(output[secondsRange])) ?? 0
                
                let currentTime = hours * 3600 + minutes * 60 + seconds
                return min(currentTime / duration, 1.0)
            }
        }
        
        return nil
    }
    
    /// Parse yt-dlp download progress
    /// - Parameter output: The yt-dlp output string
    /// - Returns: Progress percentage (0.0 to 100.0) if found
    static func parseYtDlpProgress(from output: String) -> Double? {
        let progressPattern = #"\[download\]\s+(\d+\.?\d*)%"#
        if let regex = try? NSRegularExpression(pattern: progressPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)) {
            let matchRange = Range(match.range(at: 1), in: output)!
            let percentString = String(output[matchRange])
            return Double(percentString)
        }
        return nil
    }
}

// MARK: - Private Actors

/// Thread-safe data buffer
private actor DataBuffer {
    private var buffer = Data()
    
    var data: Data {
        buffer
    }
    
    func appendData(_ data: Data) {
        buffer.append(data)
    }
}

/// Thread-safe process state manager
private actor ProcessStateManager {
    private var hasResumed = false
    
    func markResumedAndCleanup(_ cleanup: @Sendable () -> Void) -> Bool {
        if hasResumed {
            return true
        }
        hasResumed = true
        cleanup()
        return false
    }
}

// MARK: - Errors

enum ProcessExecutorError: LocalizedError {
    case launchFailed(String)
    case timeout(TimeInterval)
    case executionFailed(exitCode: Int32, error: String?)
    
    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Failed to launch process: \(message)"
        case .timeout(let duration):
            return "Process timed out after \(Int(duration)) seconds"
        case .executionFailed(let exitCode, let error):
            return "Process failed with exit code \(exitCode): \(error ?? "Unknown error")"
        }
    }
}