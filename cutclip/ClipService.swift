//
//  ClipService.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

@MainActor
class ClipService: ObservableObject, Sendable {
    private let binaryManager: BinaryManager
    @Published var currentJob: ClipJob?

    nonisolated init(binaryManager: BinaryManager) {
        self.binaryManager = binaryManager
    }

    nonisolated func clipVideo(inputPath: String, job: ClipJob) async throws -> String {
        let ffmpegPath = await MainActor.run { binaryManager.ffmpegPath }
        guard let ffmpegPath = ffmpegPath else {
            throw ClipError.binaryNotFound("FFmpeg not configured")
        }

        // Enhanced input validation and sanitization
        guard !inputPath.isEmpty,
              inputPath.count <= 2048, // Reasonable path length limit
              !inputPath.contains("\0"), // Null byte injection
              !inputPath.contains("\n"), // Newline injection
              !inputPath.contains("\r") else { // Carriage return injection
            throw ClipError.invalidInput("Invalid input file path")
        }

        // Verify input file exists and is readable
        guard FileManager.default.fileExists(atPath: inputPath),
              FileManager.default.isReadableFile(atPath: inputPath) else {
            throw ClipError.invalidInput("Input file does not exist or is not readable")
        }

        // Validate time format and values
        guard ValidationUtils.isValidTimeFormat(job.startTime),
              ValidationUtils.isValidTimeFormat(job.endTime) else {
            throw ClipError.invalidInput("Invalid time format. Use HH:MM:SS")
        }

        // Ensure start time is before end time
        guard let startSeconds = ValidationUtils.timeStringToSeconds(job.startTime),
              let endSeconds = ValidationUtils.timeStringToSeconds(job.endTime),
              startSeconds < endSeconds else {
            throw ClipError.invalidInput("Start time must be before end time")
        }

        // Create secure output path in Downloads directory
        let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let timestamp = DateFormatter.yyyyMMddHHmmss.string(from: Date())
        let outputFileName = "CutClip_\(timestamp).mp4"
        let outputPath = downloadsPath.appendingPathComponent(outputFileName).path

        // Ensure output directory exists and is writable
        try FileManager.default.createDirectory(at: downloadsPath, withIntermediateDirectories: true)
        guard FileManager.default.isWritableFile(atPath: downloadsPath.path) else {
            throw ClipError.diskSpaceError("Cannot write to Downloads directory")
        }

        // Use an actor to manage state instead of captured variables
        let stateManager = ProcessStateManager()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)

            // Secure argument construction - no shell interpolation
            var arguments = [
                "-i", inputPath,          // Input file (already validated)
                "-ss", job.startTime,     // Start time (already validated)
                "-to", job.endTime        // End time (already validated)
            ]

            // Apply video filter if aspect ratio requires cropping
            if let cropFilter = job.aspectRatio.cropFilter {
                // Apply video filter and re-encode for quality
                arguments.append(contentsOf: [
                    "-vf", sanitizeFilterString(cropFilter),
                    "-c:v", "libx264",        // Video codec for encoding
                    "-crf", "18",             // High quality (lower = better)
                    "-preset", "veryfast",    // Fast encoding preset
                    "-c:a", "copy"            // Copy audio without re-encoding
                ])
            } else {
                // Original behavior - stream copy for speed
                arguments.append(contentsOf: ["-c", "copy"])
            }

            // Common arguments
            arguments.append(contentsOf: [
                "-avoid_negative_ts", "make_zero", // Handle negative timestamps
                "-y",                              // Overwrite output file
                outputPath                         // Output file (constructed securely)
            ])

            process.arguments = arguments

            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe

            // Security: Set restrictive environment
            process.environment = [
                "PATH": "/usr/bin:/bin", // Minimal PATH
                "HOME": NSTemporaryDirectory() // Sandbox home directory
            ]

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty, let self = self {
                    let output = String(data: data, encoding: .utf8) ?? ""

                    Task {
                        // Check for duration on initial output
                        if await stateManager.totalDuration == nil, let duration = self.parseDuration(from: output) {
                            await stateManager.setTotalDuration(duration)
                        }

                        // Parse progress using total duration
                        if let totalDuration = await stateManager.totalDuration,
                           let progress = self.parseCurrentTime(from: output) {
                            let percentage = min(progress / totalDuration, 1.0)
                            await self.updateProgress(percentage)
                        }
                    }

                    // Log only non-sensitive information
                    if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("FFmpeg: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
            }

            process.terminationHandler = { process in
                Task {
                    let didResume = await stateManager.markResumedAndCleanup {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        if process.isRunning {
                            process.terminate()
                            // Force kill if doesn't terminate within 5 seconds
                            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                                if process.isRunning {
                                    process.interrupt()
                                }
                            }
                        }
                    }

                    if !didResume {
                        if process.terminationStatus == 0 {
                            // Verify output file was created and has reasonable size
                            if FileManager.default.fileExists(atPath: outputPath) {
                                do {
                                    let attributes = try FileManager.default.attributesOfItem(atPath: outputPath)
                                    let fileSize = attributes[.size] as? Int64 ?? 0

                                    if fileSize > 1000 { // At least 1KB
                                        continuation.resume(returning: outputPath)
                                    } else {
                                        continuation.resume(throwing: ClipError.processError("Output file is too small or empty"))
                                    }
                                } catch {
                                    continuation.resume(throwing: ClipError.processError("Failed to verify output file: \(error.localizedDescription)"))
                                }
                            } else {
                                continuation.resume(throwing: ClipError.processError("Output file was not created"))
                            }
                        } else {
                            let errorData = try? pipe.fileHandleForReading.readToEnd()
                            let errorOutput = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                            continuation.resume(throwing: ClipError.processError("FFmpeg failed: \(errorOutput)"))
                        }
                    }
                }
            }

            // Security timeout - prevent runaway processes
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000_000) // 10 minutes max
                let didResume = await stateManager.markResumedAndCleanup {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning {
                        process.terminate()
                    }
                }
                if !didResume {
                    continuation.resume(throwing: ClipError.processError("Video processing timed out"))
                }
            }

            do {
                try process.run()
            } catch {
                Task {
                    _ = await stateManager.markResumedAndCleanup {
                        pipe.fileHandleForReading.readabilityHandler = nil
                    }
                    continuation.resume(throwing: ClipError.processError("Failed to start FFmpeg: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Helper Methods

    @MainActor
    private func updateProgress(_ progress: Double) {
        // Update progress for current job if needed
        let percentage = Int(progress * 100)
        print("Clipping progress: \(percentage)%")
        if let job = currentJob {
            let updatedJob = ClipJob(
                url: job.url,
                startTime: job.startTime,
                endTime: job.endTime,
                aspectRatio: job.aspectRatio,
                status: .clipping,
                progress: progress,
                downloadedFilePath: job.downloadedFilePath,
                outputFilePath: job.outputFilePath,
                errorMessage: job.errorMessage,
                videoInfo: job.videoInfo
            )
            currentJob = updatedJob
        }
    }

    private nonisolated func parseDuration(from output: String) -> Double? {
        // Look for duration in format "Duration: 00:01:23.45"
        let durationPattern = #"Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})"#
        let regex = try? NSRegularExpression(pattern: durationPattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)

        if let match = regex?.firstMatch(in: output, range: range) {
            let hoursRange = Range(match.range(at: 1), in: output)!
            let minutesRange = Range(match.range(at: 2), in: output)!
            let secondsRange = Range(match.range(at: 3), in: output)!

            let hours = Double(String(output[hoursRange])) ?? 0
            let minutes = Double(String(output[minutesRange])) ?? 0
            let seconds = Double(String(output[secondsRange])) ?? 0

            return hours * 3600 + minutes * 60 + seconds
        }

        return nil
    }

    private nonisolated func parseCurrentTime(from output: String) -> Double? {
        // Look for time in format "time=00:00:12.34"
        let timePattern = #"time=(\d{2}):(\d{2}):(\d{2}\.\d{2})"#
        let regex = try? NSRegularExpression(pattern: timePattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)

        if let match = regex?.firstMatch(in: output, range: range) {
            let hoursRange = Range(match.range(at: 1), in: output)!
            let minutesRange = Range(match.range(at: 2), in: output)!
            let secondsRange = Range(match.range(at: 3), in: output)!

            let hours = Double(String(output[hoursRange])) ?? 0
            let minutes = Double(String(output[minutesRange])) ?? 0
            let seconds = Double(String(output[secondsRange])) ?? 0

            return hours * 3600 + minutes * 60 + seconds
        }

        return nil
    }

    private nonisolated func generateOutputFileName(for job: ClipJob) -> String {
        let timestamp = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        }.string(from: Date())

        let aspectRatioSuffix = job.aspectRatio == .original ? "" : "_\(job.aspectRatio.rawValue)"
        let timeRange = "\(job.startTime.replacingOccurrences(of: ":", with: "-"))_to_\(job.endTime.replacingOccurrences(of: ":", with: "-"))"

        return "CutClip_\(timestamp)_\(timeRange)\(aspectRatioSuffix).mp4"
    }

    private nonisolated func getOutputDirectory() -> URL {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return downloadsDir
    }

    nonisolated private func updateJobProgress(_ progress: Double) {
        Task { @MainActor in
            guard let job = currentJob else { return }
            let updatedJob = ClipJob(
                url: job.url,
                startTime: job.startTime,
                endTime: job.endTime,
                aspectRatio: job.aspectRatio,
                status: job.status,
                progress: progress,
                downloadedFilePath: job.downloadedFilePath,
                outputFilePath: job.outputFilePath,
                errorMessage: job.errorMessage,
                videoInfo: job.videoInfo
            )
            currentJob = updatedJob
        }
    }

    nonisolated func isValidTimeFormat(_ timeString: String) -> Bool {
        let timePattern = #"^\d{2}:\d{2}:\d{2}$"#
        let regex = try? NSRegularExpression(pattern: timePattern)
        let range = NSRange(timeString.startIndex..<timeString.endIndex, in: timeString)
        return regex?.firstMatch(in: timeString, range: range) != nil
    }

    nonisolated func convertTimeToSeconds(_ timeString: String) -> Double? {
        let components = timeString.split(separator: ":").compactMap { Double($0) }
        guard components.count == 3 else { return nil }

        let hours = components[0]
        let minutes = components[1]
        let seconds = components[2]

        return hours * 3600 + minutes * 60 + seconds
    }

    // MARK: - Input Sanitization

    private nonisolated func sanitizeFilePath(_ path: String) throws -> String {
        // Remove control characters that could break the process
        let sanitized = path.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")

        // SECURITY: Reject paths with dangerous command injection patterns
        let dangerousPatterns = [";", "|", "&", "`", "$", "\\", "../", "~"]
        for pattern in dangerousPatterns {
            if sanitized.contains(pattern) {
                print("🚨 SECURITY: Rejecting file path with dangerous pattern: \(pattern)")
                throw ClipError.invalidInput("Invalid file path: contains dangerous characters")
            }
        }

        // Ensure path is absolute to prevent relative path attacks
        if !sanitized.hasPrefix("/") {
            throw ClipError.invalidInput("Invalid file path: must be absolute path")
        }

        return sanitized
    }

    private nonisolated func sanitizeTimeString(_ timeString: String) -> String {
        // Only allow digits, colons, and dots for time format HH:MM:SS.mmm
        let allowedCharacters = CharacterSet(charactersIn: "0123456789:.")
        return String(timeString.unicodeScalars.filter { allowedCharacters.contains($0) })
    }

    private nonisolated func sanitizeFilterString(_ filterString: String) -> String {
        // Allow the full set of characters that can legitimately appear in an
        // FFmpeg filter expression. These are NOT executed by a shell – they are
        // passed straight to the FFmpeg binary – so they do not create a code-
        // injection surface, but removing them breaks the syntax.
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:=,.-_*()/\\"
        )
        return String(filterString.unicodeScalars.filter { allowedCharacters.contains($0) })
    }
}

// Thread-safe actor for process state management
private actor ProcessStateManager {
    private var hasResumed = false
    private(set) var totalDuration: Double?

    func setTotalDuration(_ duration: Double) {
        if totalDuration == nil {
            totalDuration = duration
        }
    }

    func markResumedAndCleanup(_ cleanup: () -> Void) -> Bool {
        if hasResumed {
            return true
        }
        hasResumed = true
        cleanup()
        return false
    }
}

enum ClipError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case clippingFailed(String)
    case processError(String)
    case outputFileNotFound
    case invalidTimeFormat
    case endTimeBeforeStartTime
    case diskSpaceError(String)
    case fileSystemError(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(_):
            return "Setup required. Please configure required tools in Settings."
        case .clippingFailed(_):
            return "Video processing failed. This video may be restricted."
        case .processError(_):
            return "Video processing failed. This video may be restricted."
        case .outputFileNotFound:
            return "Unable to save video. Please check your disk space."
        case .invalidTimeFormat:
            return "Start and end times must be in HH:MM:SS format."
        case .endTimeBeforeStartTime:
            return "End time must be after start time."
        case .diskSpaceError(_):
            return "Unable to save video. Please check your disk space."
        case .fileSystemError(_):
            return "Unable to save video. Please check your disk space."
        case .invalidInput(let message):
            return message
        }
    }

    func toAppError() -> AppError {
        switch self {
        case .binaryNotFound(_):
            return .binaryNotFound("Setup required. Please configure required tools in Settings.")
        case .clippingFailed(_):
            return .clippingFailed("Video processing failed. This video may be restricted.")
        case .processError(_):
            return .clippingFailed("Video processing failed. This video may be restricted.")
        case .outputFileNotFound:
            return .fileSystem("Unable to save video. Please check your disk space.")
        case .invalidTimeFormat:
            return .invalidInput("Start and end times must be in HH:MM:SS format.")
        case .endTimeBeforeStartTime:
            return .invalidInput("End time must be after start time.")
        case .diskSpaceError(_):
            return .diskSpace("Unable to save video. Please check your disk space.")
        case .fileSystemError(_):
            return .fileSystem("Unable to save video. Please check your disk space.")
        case .invalidInput(let message):
            return .invalidInput(message)
        }
    }
}

extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }

    static let yyyyMMddHHmmss: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}