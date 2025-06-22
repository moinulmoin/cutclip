//
//  BinaryManager.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation

@MainActor
class BinaryManager: ObservableObject, Sendable {
    @Published var ytDlpPath: String?
    @Published var ffmpegPath: String?
    @Published var isConfigured: Bool = false

    private let appSupportDirectory: URL

    nonisolated init() {
        // Create app support directory
        let fileManager = FileManager.default
        let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDirectory = supportDir.appendingPathComponent("CutClip")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)

        // Check for existing binaries
        Task { @MainActor in
            self.checkBinaries()
        }
    }

    var ytDlpURL: URL? {
        guard let path = ytDlpPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var ffmpegURL: URL? {
        guard let path = ffmpegPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    func checkBinaries() {
        // Check in bin subdirectory (auto-downloaded location)
        let binDirectory = appSupportDirectory.appendingPathComponent("bin")
        let ytDlpFile = binDirectory.appendingPathComponent("yt-dlp")
        let ffmpegFile = binDirectory.appendingPathComponent("ffmpeg")

        if FileManager.default.fileExists(atPath: ytDlpFile.path) {
            ytDlpPath = ytDlpFile.path
        }

        if FileManager.default.fileExists(atPath: ffmpegFile.path) {
            ffmpegPath = ffmpegFile.path
        }

        updateConfigurationStatus()
    }

    func setBinaryPath(for binary: BinaryType, path: String) {
        switch binary {
        case .ytDlp:
            ytDlpPath = path
        case .ffmpeg:
            ffmpegPath = path
        }
        updateConfigurationStatus()
    }

    nonisolated func verifyBinary(_ binary: BinaryType) async -> Bool {
        let (path, testArgs) = await MainActor.run {
            switch binary {
            case .ytDlp:
                return (self.ytDlpPath, ["--version"])
            case .ffmpeg:
                return (self.ffmpegPath, ["-version"])
            }
        }

        guard let binaryPath = path else { return false }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = testArgs

            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    nonisolated func verifyAllBinaries() async -> Bool {
        let ytDlpValid = await verifyBinary(.ytDlp)
        let ffmpegValid = await verifyBinary(.ffmpeg)
        return ytDlpValid && ffmpegValid
    }

    private func updateConfigurationStatus() {
        isConfigured = ytDlpPath != nil && ffmpegPath != nil
    }
}

enum BinaryType: Sendable {
    case ytDlp
    case ffmpeg

    var displayName: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .ffmpeg: return "FFmpeg"
        }
    }
}