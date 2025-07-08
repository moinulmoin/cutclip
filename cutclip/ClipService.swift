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
    private let processExecutor = ProcessExecutor()
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

        // Build FFmpeg arguments
        var arguments = [
            "-i", inputPath,          // Input file (already validated)
            "-ss", job.startTime,     // Start time (already validated)
            "-to", job.endTime        // End time (already validated)
        ]

        // Apply video filter if aspect ratio requires cropping or quality scaling
        var videoFilters: [String] = []
        
        // Add crop filter if needed for aspect ratio
        if let cropFilter = job.aspectRatio.cropFilter {
            videoFilters.append(cropFilter)
        }
        
        // Add scale filter for output quality (always scale to target quality)
        if let scaleFilter = job.aspectRatio.scaleFilter(for: job.quality) {
            videoFilters.append(scaleFilter)
        } else if job.quality.lowercased() != "best" {
            // For "Auto" aspect ratio, still scale to target quality if specified
            if let height = Int(job.quality.lowercased().replacingOccurrences(of: "p", with: "")) {
                // Ensure height is even for video encoding compatibility
                let evenHeight = height % 2 == 0 ? height : height + 1
                videoFilters.append("scale=-2:\(evenHeight)")
            }
        }
        
        if !videoFilters.isEmpty {
            // Apply video filters and re-encode for quality
            let combinedFilter = videoFilters.joined(separator: ",")
            arguments.append(contentsOf: [
                "-map", "0:v?",           // Map video stream if present
                "-map", "0:a?",           // Map audio stream if present
                "-vf", sanitizeFilterString(combinedFilter),
                "-c:v", "libx264",        // Video codec for encoding
                "-crf", "18",             // High quality (lower = better)
                "-preset", "veryfast",    // Fast encoding preset
                "-c:a", "copy"            // Copy audio without re-encoding
            ])
        } else {
            // When using stream copy, ensure we explicitly map streams
            arguments.append(contentsOf: [
                "-map", "0",              // Map all streams from input
                "-c", "copy",             // Copy all codecs
                "-movflags", "+faststart" // Optimize for streaming
            ])
        }

        // Common arguments
        arguments.append(contentsOf: [
            "-avoid_negative_ts", "make_zero", // Handle negative timestamps
            "-y",                              // Overwrite output file
            outputPath                         // Output file (constructed securely)
        ])

        // Debug: Log the FFmpeg command
        print("🎬 FFmpeg command: \(ffmpegPath) \(arguments.joined(separator: " "))")
        print("📊 Job details - Quality: \(job.quality), Aspect: \(job.aspectRatio.rawValue)")

        // Track total duration for progress calculation using an actor
        let durationTracker = DurationTracker()
        
        // Configure process execution
        let config = ProcessConfiguration(
            executablePath: ffmpegPath,
            arguments: arguments,
            timeout: 600, // 10 minutes
            outputHandler: { [weak self] output in
                Task {
                    // Parse FFmpeg progress with thread-safe duration tracking
                    if let progress = await durationTracker.parseProgress(from: output) {
                        await MainActor.run { [weak self] in
                            self?.updateProgress(progress)
                        }
                    }
                }
                
                // Log non-sensitive information
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    print("FFmpeg: \(trimmed)")
                }
            }
        )

        // Execute the process
        let result = try await processExecutor.execute(config)
        
        // Handle the result
        if result.isSuccess {
            // Verify output file was created and has reasonable size
            if FileManager.default.fileExists(atPath: outputPath) {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: outputPath)
                    let fileSize = attributes[.size] as? Int64 ?? 0

                    if fileSize > 1000 { // At least 1KB
                        print("✅ Output file created: \(outputPath) (\(fileSize) bytes)")
                        return outputPath
                    } else {
                        print("❌ Output file too small: \(fileSize) bytes")
                        throw ClipError.processError("Output file is too small or empty")
                    }
                } catch {
                    throw ClipError.processError("Failed to verify output file: \(error.localizedDescription)")
                }
            } else {
                throw ClipError.processError("Output file was not created")
            }
        } else {
            let errorOutput = result.errorString ?? result.outputString ?? "Unknown error"
            print("❌ FFmpeg process failed with status: \(result.exitCode)")
            print("❌ Error output: \(errorOutput)")
            throw ClipError.processError("FFmpeg failed: \(errorOutput)")
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
                quality: job.quality,
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
                quality: job.quality,
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
        // FFmpeg filters are passed directly to the FFmpeg binary as arguments,
        // not through a shell, so we don't need aggressive sanitization.
        // We just need to ensure no null bytes or newlines that could break argument parsing.
        return filterString
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
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

// MARK: - Thread-safe duration tracking for FFmpeg progress

private actor DurationTracker {
    private var totalDuration: Double?
    
    func parseProgress(from output: String) -> Double? {
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
}