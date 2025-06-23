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

        print("DEBUG ClipService: Input path received: \(inputPath)")
        print("DEBUG ClipService: File exists at input path: \(FileManager.default.fileExists(atPath: inputPath))")

        // Generate output filename
        let outputFileName = generateOutputFileName(for: job)
        let outputPath = getOutputDirectory().appendingPathComponent(outputFileName).path

        let sanitizedInputPath = sanitizeFilePath(inputPath)
        print("DEBUG ClipService: Sanitized input path: \(sanitizedInputPath)")
        print("DEBUG ClipService: File exists at sanitized path: \(FileManager.default.fileExists(atPath: sanitizedInputPath))")

        // Build FFmpeg arguments with input sanitization
        var arguments = [
            "-i", sanitizedInputPath,
            "-ss", sanitizeTimeString(job.startTime),
            "-to", sanitizeTimeString(job.endTime),
            "-c:v", "libx264",
            "-c:a", "aac",
            "-preset", "medium",
            "-crf", "23"
        ]

        // Add crop filter if aspect ratio is not original
        if let cropFilter = job.aspectRatio.cropFilter {
            arguments.append(contentsOf: ["-vf", sanitizeFilterString(cropFilter)])
        }

        arguments.append(contentsOf: [
            "-avoid_negative_ts", "make_zero",
            "-y", // Overwrite output file
            sanitizeFilePath(outputPath)
        ])

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardError = pipe

            // Use thread-safe actor for progress tracking
            let progressTracker = ProgressTracker()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    Task {
                        await progressTracker.appendData(data)
                        let output = String(data: data, encoding: .utf8) ?? ""

                        // Parse duration on first occurrence
                        if await progressTracker.totalDuration == nil {
                            if let duration = parseDuration(from: output) {
                                await progressTracker.setTotalDuration(duration)
                            }
                        }

                        // Parse progress
                        if let duration = await progressTracker.totalDuration,
                           let currentTime = parseCurrentTime(from: output) {
                            let progress = min(currentTime / duration, 1.0)
                            await MainActor.run {
                                self.updateJobProgress(progress)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil

                Task {
                    if process.terminationStatus == 0 {
                        // Verify output file exists
                        if FileManager.default.fileExists(atPath: outputPath) {
                            continuation.resume(returning: outputPath)
                        } else {
                            continuation.resume(throwing: ClipError.outputFileNotFound)
                        }
                    } else {
                        let outputData = await progressTracker.outputData
                        let errorOutput = String(data: outputData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ClipError.clippingFailed(errorOutput))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ClipError.processError(error.localizedDescription))
            }
        }
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
                errorMessage: job.errorMessage
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

    private nonisolated func sanitizeFilePath(_ path: String) -> String {
        // Remove only null bytes and control characters that could break the process
        let sanitized = path.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
        
        // For security, check for command injection patterns but don't remove valid file path characters
        let dangerousPatterns = [";", "|", "&", "`"]
        for pattern in dangerousPatterns {
            if sanitized.contains(pattern) {
                // Log potential security issue but don't modify the path
                print("Warning: File path contains potentially dangerous pattern: \(pattern)")
            }
        }
        
        // Return the path as-is since Process.arguments handles escaping automatically
        return sanitized
    }

    private nonisolated func sanitizeTimeString(_ timeString: String) -> String {
        // Only allow digits, colons, and dots for time format HH:MM:SS.mmm
        let allowedCharacters = CharacterSet(charactersIn: "0123456789:.")
        return String(timeString.unicodeScalars.filter { allowedCharacters.contains($0) })
    }

    private nonisolated func sanitizeFilterString(_ filterString: String) -> String {
        // Allow only safe characters for video filters
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:=,.-_")
        return String(filterString.unicodeScalars.filter { allowedCharacters.contains($0) })
    }
}

// Thread-safe actor for progress tracking
private actor ProgressTracker {
    private(set) var outputData = Data()
    private(set) var totalDuration: Double?

    func appendData(_ data: Data) {
        outputData.append(data)
    }

    func setTotalDuration(_ duration: Double) {
        totalDuration = duration
    }
}

// Global functions for parsing (nonisolated)
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

enum ClipError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case clippingFailed(String)
    case processError(String)
    case outputFileNotFound
    case invalidTimeFormat
    case endTimeBeforeStartTime
    case diskSpaceError(String)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let message):
            return "Binary not found: \(message)"
        case .clippingFailed(let message):
            return "Clipping failed: \(message)"
        case .processError(let message):
            return "Process error: \(message)"
        case .outputFileNotFound:
            return "Output file was not created"
        case .invalidTimeFormat:
            return "Invalid time format. Use HH:MM:SS"
        case .endTimeBeforeStartTime:
            return "End time must be after start time"
        case .diskSpaceError(let message):
            return "Disk space error: \(message)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }

    func toAppError() -> AppError {
        switch self {
        case .binaryNotFound(let message):
            return .binaryNotFound(message)
        case .clippingFailed(let message):
            return .clippingFailed(message)
        case .processError(let message):
            return .clippingFailed(message)
        case .outputFileNotFound:
            return .fileSystem("Output file was not created")
        case .invalidTimeFormat:
            return .invalidInput("Invalid time format. Use HH:MM:SS")
        case .endTimeBeforeStartTime:
            return .invalidInput("End time must be after start time")
        case .diskSpaceError(let message):
            return .diskSpace(message)
        case .fileSystemError(let message):
            return .fileSystem(message)
        }
    }
}

extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}