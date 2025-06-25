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
    @Published var errorMessage: String?
    @Published var isVerifying: Bool = false

    private let appSupportDirectory: URL

    // Task management
    private var verificationTask: Task<Void, Never>?

    nonisolated init() {
        // Create app support directory
        let fileManager = FileManager.default
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
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

        // Auto-verify binaries if both are present
        if isConfigured {
            // Cancel any existing verification task
            verificationTask?.cancel()

            verificationTask = Task {
                await verifyBinariesWithFeedback()
                await MainActor.run {
                    self.verificationTask = nil
                }
            }
        }
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
            } catch {
                print("❌ Failed to verify \(binary.displayName): \(error)")
                continuation.resume(returning: false)
                return
            }

            process.waitUntilExit()
            continuation.resume(returning: process.terminationStatus == 0)
        }
    }

    nonisolated func verifyAllBinaries() async -> Bool {
        let ytDlpValid = await verifyBinary(.ytDlp)
        let ffmpegValid = await verifyBinary(.ffmpeg)
        return ytDlpValid && ffmpegValid
    }

    /// Verify binaries with user feedback
    func verifyBinariesWithFeedback() async {
        isVerifying = true
        errorMessage = nil

        defer {
            isVerifying = false
        }

        let ytDlpValid = await verifyBinary(.ytDlp)
        let ffmpegValid = await verifyBinary(.ffmpeg)

        if !ytDlpValid {
            errorMessage = "yt-dlp verification failed. The binary may be corrupted or incompatible."
            isConfigured = false
            print("❌ yt-dlp verification failed")
            return
        }

        if !ffmpegValid {
            errorMessage = "FFmpeg verification failed. The binary may be corrupted or incompatible."
            isConfigured = false
            print("❌ FFmpeg verification failed")
            return
        }

        print("✅ All binaries verified successfully")
        isConfigured = true
    }

    private func updateConfigurationStatus() {
        let hasAllBinaries = ytDlpPath != nil && ffmpegPath != nil

        // Only set as configured if we have all binaries and no error
        if hasAllBinaries && errorMessage == nil {
            isConfigured = true
        } else {
            isConfigured = false
        }
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