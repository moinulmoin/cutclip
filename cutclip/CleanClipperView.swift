//
//  CleanClipperView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/28/25.
//

import SwiftUI

struct CleanClipperView: View {
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

    // Quality and aspect ratio options
    let qualityOptions = ["720p", "1080p", "1440p", "2160p"]
    let aspectRatioOptions: [ClipJob.AspectRatio] = [.original, .nineSixteen, .oneOne, .fourThree]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Clean Header
                headerSection
                
                // Main Content
                VStack(spacing: CleanDS.Spacing.sectionSpacing) {
                    // URL Input Section
                    urlInputSection
                    
                    // Video Preview (if loaded)
                    if let videoInfo = loadedVideoInfo {
                        CleanVideoPreview(videoInfo: videoInfo)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                    
                    // Clip Settings Section
                    clipSettingsSection
                    
                    // Progress Section (if processing)
                    if isProcessing {
                        CleanProgressSection(
                            title: "Processing Video",
                            message: processingMessage,
                            progress: processingProgress
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                    
                    // Action/Success Section
                    actionSection
                }
                .padding(CleanDS.Spacing.containerNormal)
            }
        }
        .cleanWindow()
        .cleanContent(maxWidth: 500)
        .sheet(isPresented: $showingLicenseView) {
            LicenseStatusView()
                .environmentObject(licenseManager)
                .environmentObject(usageTracker)
                .environmentObject(errorHandler)
        }
        .onAppear {
            videoInfoService = VideoInfoService(binaryManager: binaryManager)
        }
        .onDisappear {
            // Clean up tasks when view disappears
            videoInfoLoadingTask?.cancel()
            processingTask?.cancel()
        }
        .animation(CleanDS.Animation.standard, value: loadedVideoInfo?.title)
        .animation(CleanDS.Animation.standard, value: isProcessing)
        .animation(CleanDS.Animation.standard, value: completedVideoPath)
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: CleanDS.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                    Text("CutClip")
                        .font(CleanDS.Typography.headline)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                    
                    Text("Create clips from YouTube videos")
                        .font(CleanDS.Typography.caption)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                }
                
                Spacer()
                
                HStack(spacing: CleanDS.Spacing.sm) {
                    // Status indicator
                    CleanStatusIndicator(
                        licenseStatus: licenseManager.licenseStatus,
                        onUpgrade: { showingLicenseView = true }
                    )
                    
                    // Settings button
                    Button(action: { showingLicenseView = true }) {
                        Image(systemName: "gearshape")
                            .font(CleanDS.Typography.body)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                    }
                    .cleanGhostButton()
                }
            }
        }
        .padding(CleanDS.Spacing.containerNormal)
        .background(CleanDS.Colors.backgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(CleanDS.Colors.borderLight),
            alignment: .bottom
        )
    }
    
    // MARK: - URL Input Section
    @ViewBuilder
    private var urlInputSection: some View {
        CleanInputWithAction(
            label: "YouTube Video URL",
            text: $urlText,
            placeholder: "https://youtube.com/watch?v=...",
            isDisabled: isProcessing || isLoadingVideoInfo,
            onTextChange: { clearVideoInfo() }
        ) {
            Button(action: loadVideoInfo) {
                HStack(spacing: CleanDS.Spacing.xs) {
                    if isLoadingVideoInfo {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CleanDS.Colors.accent)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(CleanDS.Colors.accent)
                    }
                    Text("Load Info")
                }
            }
            .cleanPrimaryButton()
            .disabled(urlText.isEmpty || isProcessing || isLoadingVideoInfo)
        }
    }
    
    // MARK: - Clip Settings Section
    @ViewBuilder
    private var clipSettingsSection: some View {
        VStack(spacing: CleanDS.Spacing.md) {
            CleanSectionHeader(title: "Clip Settings")
            
            // Time inputs
            HStack(spacing: CleanDS.Spacing.md) {
                CleanInputField(
                    label: "Start Time",
                    text: $startTime,
                    placeholder: "00:00:00",
                    isDisabled: isProcessing || isLoadingVideoInfo
                )
                
                CleanInputField(
                    label: "End Time",
                    text: $endTime,
                    placeholder: "00:00:10",
                    isDisabled: isProcessing || isLoadingVideoInfo
                )
            }
            
            // Quality and aspect ratio
            HStack(spacing: CleanDS.Spacing.md) {
                CleanPickerField(
                    label: "Quality",
                    selection: $selectedQuality,
                    options: qualityOptions,
                    isDisabled: isProcessing || isLoadingVideoInfo
                )
                
                CleanPickerField(
                    label: "Aspect Ratio",
                    selection: $selectedAspectRatio,
                    options: aspectRatioOptions,
                    isDisabled: isProcessing || isLoadingVideoInfo
                )
            }
        }
        .cleanSection()
    }
    
    // MARK: - Action Section
    @ViewBuilder
    private var actionSection: some View {
        if let videoPath = completedVideoPath {
            CleanSuccessSection(
                onOpenVideo: { openVideo(at: videoPath) },
                onShowInFinder: { showInFinder(path: videoPath) },
                onNewClip: resetState
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                removal: .opacity
            ))
        } else if !isProcessing {
            CleanActionButton(
                "Create Clip",
                icon: "scissors",
                style: .primary,
                isDisabled: urlText.isEmpty,
                action: processVideo
            )
            .transition(.opacity)
        }
    }
}

// MARK: - Video Processing Logic
extension CleanClipperView {
    
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

    // MARK: - Video Processing
    private func processVideo() {
        // Cancel any existing processing task
        processingTask?.cancel()

        processingTask = Task {
            await performVideoProcessing()
            await MainActor.run {
                self.processingTask = nil
            }
        }
    }

    @MainActor
    private func performVideoProcessing() async {
        // Show progress immediately
        isProcessing = true
        processingProgress = 0.0
        processingMessage = "Starting..."
        completedVideoPath = nil

        defer {
            // Always hide processing state when done
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
            processingMessage = "Validating inputs..."
            processingProgress = 0.1
            guard ValidationUtils.isValidYouTubeURL(urlText) else {
                throw AppError.invalidInput("Please enter a valid YouTube URL")
            }

            guard ValidationUtils.isValidTimeFormat(startTime) && ValidationUtils.isValidTimeFormat(endTime) else {
                throw AppError.invalidInput("Please enter valid time formats (HH:MM:SS)")
            }
            
            guard ValidationUtils.isValidTimeRange(start: startTime, end: endTime) else {
                throw AppError.invalidInput("Start time must be before end time")
            }

            // Check network connectivity
            processingMessage = "Checking network..."
            processingProgress = 0.2
            try await ErrorHandler.checkNetworkConnectivity()

            // Check disk space
            processingMessage = "Checking disk space..."
            processingProgress = 0.3
            try ErrorHandler.checkDiskSpace()

            // Validate quality selection
            processingMessage = "Validating quality..."
            processingProgress = 0.35
            if let videoInfo = loadedVideoInfo {
                guard ValidationUtils.isValidQualityForVideoInfo(selectedQuality, videoInfo: videoInfo) else {
                    throw AppError.invalidInput("Selected quality '\(selectedQuality)' is not available for this video. Available qualities: \(videoInfo.qualityOptions.joined(separator: ", "))")
                }
            }

            // Create clip job
            let job = ClipJob(
                url: urlText,
                startTime: startTime,
                endTime: endTime,
                aspectRatio: selectedAspectRatio,
                quality: selectedQuality,
                videoInfo: loadedVideoInfo
            )

            // Initialize services (matching original approach)
            processingMessage = "Initializing services..."
            processingProgress = 0.4
            let downloadSvc = DownloadService(binaryManager: binaryManager)
            let clipSvc = ClipService(binaryManager: binaryManager)

            // Download video
            processingMessage = "Downloading video..."
            processingProgress = 0.5
            let downloadedPath = try await downloadSvc.downloadVideo(for: job)

            // Clip video
            processingMessage = "Processing video..."
            processingProgress = 0.7
            let outputPath = try await clipSvc.clipVideo(inputPath: downloadedPath, job: job)

            // Record usage (decrement credits if not licensed)
            processingMessage = "Recording usage..."
            processingProgress = 0.9
            try await usageTracker.decrementCredits()

            // Force UI refresh after credit decrement
            await licenseManager.refreshLicenseStatus()

            // Success!
            await MainActor.run {
                self.completedVideoPath = outputPath
                self.processingProgress = 1.0
                self.processingMessage = "Complete!"
            }

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
        } catch let error as AppError {
            await MainActor.run {
                errorHandler.handle(error)
            }
        } catch {
            await MainActor.run {
                errorHandler.handle(AppError.unknown("Processing failed: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Helper Functions
    private func openVideo(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func showInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func resetState() {
        urlText = ""
        startTime = "00:00:00"
        endTime = "00:00:10"
        selectedQuality = "720p"
        selectedAspectRatio = .original
        isProcessing = false
        processingProgress = 0.0
        processingMessage = "Starting..."
        completedVideoPath = nil
        loadedVideoInfo = nil
        
        // Cancel any running tasks
        videoInfoLoadingTask?.cancel()
        processingTask?.cancel()
    }
}

#Preview {
    CleanClipperView()
        .environmentObject(BinaryManager())
        .environmentObject(ErrorHandler())
        .environmentObject(LicenseManager.shared)
        .environmentObject(UsageTracker.shared)
}