//
//  DownloadService.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

class DownloadService: ObservableObject {
    private let binaryManager: BinaryManager
    @Published var currentJob: ClipJob?
    
    init(binaryManager: BinaryManager) {
        self.binaryManager = binaryManager
    }
    
    func isValidYouTubeURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        guard let host = url.host else { return false }
        
        let validHosts = ["youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com"]
        return validHosts.contains(host.lowercased())
    }
    
    func downloadVideo(for job: ClipJob) async throws -> String {
        guard let ytDlpPath = binaryManager.ytDlpPath else {
            throw DownloadError.binaryNotFound("yt-dlp not configured")
        }
        
        guard isValidYouTubeURL(job.url) else {
            throw DownloadError.invalidURL
        }
        
        // Create temporary directory for downloads
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CutClip")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let outputTemplate = tempDir.appendingPathComponent("%(title)s.%(ext)s").path
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = [
                "--format", "best[height<=720]", // Limit to 720p for faster downloads
                "--output", outputTemplate,
                "--no-playlist",
                "--extract-flat", "false",
                job.url
            ]
            
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe
            
            var outputData = Data()
            var downloadedFilePath: String?
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputData.append(data)
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    // Parse progress from yt-dlp output
                    if let progress = self.parseProgress(from: output) {
                        DispatchQueue.main.async {
                            self.updateJobProgress(progress)
                        }
                    }
                    
                    // Look for downloaded file path
                    if let filePath = self.parseDownloadedFilePath(from: output) {
                        downloadedFilePath = filePath
                    }
                }
            }
            
            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                
                if process.terminationStatus == 0 {
                    if let filePath = downloadedFilePath {
                        continuation.resume(returning: filePath)
                    } else {
                        // Try to find the downloaded file in temp directory
                        do {
                            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                            if let videoFile = files.first(where: { !$0.hasDirectoryPath }) {
                                continuation.resume(returning: videoFile.path)
                            } else {
                                continuation.resume(throwing: DownloadError.fileNotFound)
                            }
                        } catch {
                            continuation.resume(throwing: DownloadError.downloadFailed(error.localizedDescription))
                        }
                    }
                } else {
                    let errorOutput = String(data: outputData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: DownloadError.downloadFailed(errorOutput))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: DownloadError.processError(error.localizedDescription))
            }
        }
    }
    
    private func parseProgress(from output: String) -> Double? {
        // Look for progress patterns like "[download] 25.5% of 15.30MiB"
        let progressPattern = #"\[download\]\s+(\d+\.?\d*)%"#
        let regex = try? NSRegularExpression(pattern: progressPattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        
        if let match = regex?.firstMatch(in: output, range: range) {
            let matchRange = Range(match.range(at: 1), in: output)!
            let percentString = String(output[matchRange])
            return Double(percentString)
        }
        
        return nil
    }
    
    private func parseDownloadedFilePath(from output: String) -> String? {
        // Look for patterns like "[download] Destination: /path/to/file.mp4"
        let destinationPattern = #"\[download\] Destination: (.+)"#
        let regex = try? NSRegularExpression(pattern: destinationPattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        
        if let match = regex?.firstMatch(in: output, range: range) {
            let matchRange = Range(match.range(at: 1), in: output)!
            return String(output[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private func updateJobProgress(_ progress: Double) {
        guard var job = currentJob else { return }
        job.progress = progress / 100.0
        currentJob = job
    }
}

enum DownloadError: LocalizedError {
    case binaryNotFound(String)
    case invalidURL
    case downloadFailed(String)
    case processError(String)
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let message):
            return "Binary not found: \(message)"
        case .invalidURL:
            return "Invalid YouTube URL"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .processError(let message):
            return "Process error: \(message)"
        case .fileNotFound:
            return "Downloaded file not found"
        }
    }
}