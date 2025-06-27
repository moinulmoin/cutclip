//
//  ClipperView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct ClipperView: View {
    @State private var urlText = ""
    @State private var startTime = "00:00:00"
    @State private var endTime = "00:00:10"
    @State private var selectedQuality = "720p"
    @State private var selectedAspectRatio = ClipJob.AspectRatio.original

    @EnvironmentObject private var binaryManager: BinaryManager
    @EnvironmentObject private var errorHandler: ErrorHandler
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var usageTracker: UsageTracker

    @State private var isProcessing = false
    @State private var processingProgress: Double = 0.0
    @State private var processingMessage = "Starting..."
    @State private var completedVideoPath: String?
    @State private var showingLicenseView = false

    // Video info loading
    @State private var videoInfoService: VideoInfoService?
    @State private var isLoadingVideoInfo = false
    @State private var loadedVideoInfo: VideoInfo?
    @State private var videoInfoLoadingTask: Task<Void, Never>?

    // Task management
    @State private var processingTask: Task<Void, Never>?

    // Replace dynamic quality options with fixed list
    let qualityOptions = ["720p", "1080p", "1440p", "2160p"]
    let aspectRatioOptions: [ClipJob.AspectRatio] = [.original, .nineSixteen, .oneOne, .fourThree]

    private var availableQualityOptions: [String] {
        // Always return fixed list
        return qualityOptions
    }

    @ViewBuilder
    private var usageStatusIndicator: some View {
        HStack(spacing: 8) {
            switch licenseManager.licenseStatus {
            case .licensed:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Licensed")
                        .foregroundColor(.green)
                }
            case .freeTrial(let remaining):
                HStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .foregroundColor(.blue)
                    Text("\(remaining) uses left")
                        .foregroundColor(remaining <= 1 ? .orange : .blue)
                }

                if remaining <= 1 {
                    Button("Upgrade") {
                        showingLicenseView = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundColor(.orange)
                }

            case .trialExpired, .unlicensed:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Trial expired")
                        .foregroundColor(.orange)

                    Button("Get License") {
                        showingLicenseView = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundColor(.orange)
                }
            case .unknown:
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .font(.caption)
        .fontWeight(.medium)
    }

    var body: some View {
        VStack(spacing: 32) {
            // Header with title and settings button
            HStack {
                Spacer()

                VStack(spacing: 8) {
                    Text("CutClip")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.primary)

                    usageStatusIndicator
                }

                Spacer()

                // Settings Button
                VStack {
                    Button(action: {
                        showingLicenseView = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.link)
                    .help("Settings")

                    Spacer()
                }
            }

            VStack(spacing: 24) {
                // URL Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("YouTube URL")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        TextField("https://youtube.com/watch?v=...", text: $urlText)
                            .textFieldStyle(MinimalTextFieldStyle())
                            .disabled(isProcessing || isLoadingVideoInfo)
                            .onChange(of: urlText) { _, _ in
                                clearVideoInfo()
                            }

                        Button(action: loadVideoInfo) {
                            HStack(spacing: 6) {
                                if isLoadingVideoInfo {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.primary)
                                } else {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 14))
                                }
                                Text("Load")
                                    .font(.caption.weight(.medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(urlText.isEmpty || isProcessing || isLoadingVideoInfo)
                    }
                }

                // Video Info Preview (only show when loaded)
                if let videoInfo = loadedVideoInfo {
                    videoInfoPreview(videoInfo)
                }

                // Time Settings
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("00:00:00", text: $startTime)
                                .textFieldStyle(MinimalTextFieldStyle())
                                .disabled(isProcessing || isLoadingVideoInfo)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("End")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("00:00:10", text: $endTime)
                                .textFieldStyle(MinimalTextFieldStyle())
                                .disabled(isProcessing || isLoadingVideoInfo)
                        }
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quality")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Picker("Quality", selection: $selectedQuality) {
                                ForEach(qualityOptions, id: \..self) { quality in
                                    Text(quality).tag(quality)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(isProcessing || isLoadingVideoInfo)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aspect Ratio")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Picker("Aspect Ratio", selection: $selectedAspectRatio) {
                                ForEach(aspectRatioOptions, id: \..self) { ratio in
                                    Text(ratio.rawValue).tag(ratio)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(isProcessing || isLoadingVideoInfo)
                        }
                    }
                }

                // Progress Section (only show when processing)
                if isProcessing {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            ProgressView(value: processingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .black))
                                .frame(height: 4)

                            Text(processingMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Action Button
                if let videoPath = completedVideoPath {
                    // Completion state
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Video ready!")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                        }

                        HStack(spacing: 12) {
                            Button("Open Video") {
                                openVideo(at: videoPath)
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Button("Show in Finder") {
                                showInFinder(path: videoPath)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        Button("New Clip") {
                            resetState()
                        }
                        .buttonStyle(.link)
                        .padding(.top, 8)
                    }
                } else if isProcessing {
                    // Processing loader
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.primary)

                        Text("Processing...")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                } else {
                    // Download/Process button
                    Button(action: processVideo) {
                        HStack(spacing: 8) {
                            Image(systemName: "scissors")
                            Text("Clip Video")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(urlText.isEmpty)
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 450)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingLicenseView) {
            LicenseStatusView()
                .environmentObject(licenseManager)
                .environmentObject(usageTracker)
                .environmentObject(errorHandler)
        }
        .onAppear {
            // Initialize video info service
            if videoInfoService == nil {
                videoInfoService = VideoInfoService(binaryManager: binaryManager)
            }
        }
        .onDisappear {
            // Clean up tasks when view disappears
            processingTask?.cancel()
            videoInfoLoadingTask?.cancel()
        }
    }

    private func processVideo() {
        // Cancel any existing processing task
        processingTask?.cancel()

        processingTask = Task {
            await performClipWorkflow()
            await MainActor.run {
                self.processingTask = nil
            }
        }
    }

    @MainActor
    private func performClipWorkflow() async {
        // Ensure atomic state update at start
        isProcessing = true
        processingProgress = 0.0
        completedVideoPath = nil
        processingMessage = "Starting..."

        defer {
            // Ensure processing flag is cleared even if errors occur
            isProcessing = false
        }

        do {
            // Check license and usage first
            processingMessage = "Checking license..."
            processingProgress = 0.05

            guard usageTracker.canUseApp() else {
                throw AppError.licenseError("No remaining uses. License required to continue.")
            }

            // Validate inputs
            processingMessage = "Validating..."
            processingProgress = 0.1
            try ErrorHandler.validateTimeInputs(startTime: startTime, endTime: endTime)

            // Check network connectivity
            processingMessage = "Checking connection..."
            processingProgress = 0.2
            try await ErrorHandler.checkNetworkConnectivity()

            // Check disk space
            processingMessage = "Checking disk space..."
            processingProgress = 0.3
            try ErrorHandler.checkDiskSpace()

            // Create clip job
            let job = ClipJob(
                url: urlText,
                startTime: startTime,
                endTime: endTime,
                aspectRatio: selectedAspectRatio,
                quality: selectedQuality,
                videoInfo: loadedVideoInfo
            )

            // Initialize services
            let downloadSvc = DownloadService(binaryManager: binaryManager)
            let clipSvc = ClipService(binaryManager: binaryManager)

            // Download video
            processingMessage = "Downloading video..."
            processingProgress = 0.4
            let downloadedPath = try await downloadSvc.downloadVideo(for: job)

            // Clip video
            processingMessage = "Trimming video..."
            processingProgress = 0.7
            let outputPath = try await clipSvc.clipVideo(inputPath: downloadedPath, job: job)

            // Record usage (decrement credits if not licensed)
            processingMessage = "Recording usage..."
            processingProgress = 0.9
            try await usageTracker.decrementCredits()

            // Force UI refresh after credit decrement
            await licenseManager.refreshLicenseStatus()

            // Complete - atomic state update
            processingMessage = "Complete!"
            processingProgress = 1.0
            completedVideoPath = outputPath

        } catch let error as DownloadError {
            await MainActor.run {
                errorHandler.handle(error.toAppError())
            }
        } catch let error as ClipError {
            await MainActor.run {
                errorHandler.handle(error.toAppError())
            }
        } catch let error as UsageError {
            await MainActor.run {
                errorHandler.handle(AppError.licenseError(error.localizedDescription))
            }
        } catch {
            await MainActor.run {
                errorHandler.handle(error)
            }
        }
    }

    private func openVideo(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func showInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func resetState() {
        completedVideoPath = nil
        processingProgress = 0.0
        processingMessage = "Starting..."
        urlText = ""
        startTime = "00:00:00"
        endTime = "00:00:10"
        selectedQuality = "720p"
        selectedAspectRatio = .original
        clearVideoInfo()
    }

    // MARK: - Video Info Loading

    private func loadVideoInfo() {
        guard !urlText.isEmpty else { return }
        guard let service = videoInfoService else { return }

        // Cancel any existing loading task
        videoInfoLoadingTask?.cancel()

        videoInfoLoadingTask = Task {
            await performVideoInfoLoad(service: service)
            await MainActor.run {
                self.videoInfoLoadingTask = nil
            }
        }
    }

    @MainActor
    private func performVideoInfoLoad(service: VideoInfoService) async {
        isLoadingVideoInfo = true
        defer {
            isLoadingVideoInfo = false
        }

        do {
            let videoInfo = try await service.loadVideoInfo(for: urlText)

            // Validate the loaded video info
            guard ValidationUtils.isValidVideoInfo(videoInfo) else {
                throw VideoInfoError.parsingFailed("Invalid video information received")
            }

            loadedVideoInfo = videoInfo

            // Update quality selection if current selection is not available
            if !videoInfo.qualityOptions.contains(selectedQuality) {
                selectedQuality = videoInfo.qualityOptions.first ?? "Best"
            }

        } catch let error as VideoInfoError {
            await MainActor.run {
                errorHandler.handle(error.toAppError())
            }
        } catch {
            await MainActor.run {
                errorHandler.handle(AppError.unknown("Failed to load video information: \(error.localizedDescription)"))
            }
        }
    }

    private func clearVideoInfo() {
        loadedVideoInfo = nil
        // Reset quality selection to default when clearing
        if !qualityOptions.contains(selectedQuality) {
            selectedQuality = "720p"
        }
    }

    @ViewBuilder
    private func videoInfoPreview(_ videoInfo: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                AsyncImage(url: URL(string: videoInfo.thumbnailURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(NSColor.systemGray))
                        .overlay(
                            Image(systemName: "play.rectangle")
                                .foregroundColor(.secondary)
                                .font(.title2)
                        )
                }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Video details
                VStack(alignment: .leading, spacing: 4) {
                    Text(videoInfo.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        // Duration
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(videoInfo.durationFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Channel
                        if let channelName = videoInfo.channelName {
                            HStack(spacing: 4) {
                                Image(systemName: "person.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(channelName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Quality and captions info
                    HStack(spacing: 12) {
                        // Available qualities
                        HStack(spacing: 4) {
                            Image(systemName: "tv")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text("\(videoInfo.availableFormats.count) qualities")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        // Captions
                        if videoInfo.hasCaptions {
                            HStack(spacing: 4) {
                                Image(systemName: "captions.bubble")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Text("Captions")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Spacer()
            }

            // Description (if available)
            if let description = videoInfo.truncatedDescription {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
        .cornerRadius(8)
    }
}

// MARK: - Custom Styles

struct MinimalTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
            .cornerRadius(8)
            .font(.system(.callout, design: .monospaced))
    }
}


#Preview {
    ClipperView()
}