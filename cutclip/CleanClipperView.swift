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
    
    // UX state management
    @State private var showCompletionView = false
    @State private var savedVideoURL = ""

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
                    
                    // Video Preview (if loaded and not showing completion)
                    if let videoInfo = loadedVideoInfo, !showCompletionView {
                        CleanVideoPreview(videoInfo: videoInfo)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                    
                    // Clip Settings Section
                    clipSettingsSection
                    
                    // Progress Section (if processing and not showing completion)
                    if isProcessing && !showCompletionView {
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
        if loadedVideoInfo == nil {
            // Full URL input when no video is loaded
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
        } else {
            // Compact URL display when video is loaded
            VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                CleanLabel(text: "YouTube Video URL")
                
                HStack(spacing: CleanDS.Spacing.md) {
                    HStack(spacing: CleanDS.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(CleanDS.Colors.success)
                            .font(CleanDS.Typography.body)
                        
                        Text(urlText)
                            .font(CleanDS.Typography.body)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    CleanActionButton("Change", style: .secondary) {
                        clearVideoInfo()
                        urlText = ""
                    }
                    .disabled(isProcessing)
                }
                .padding(CleanDS.Spacing.md)
                .background(CleanDS.Colors.backgroundSecondary)
                .cornerRadius(CleanDS.Radius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: CleanDS.Radius.medium)
                        .stroke(CleanDS.Colors.borderLight, lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Clip Settings Section
    @ViewBuilder
    private var clipSettingsSection: some View {
        if loadedVideoInfo != nil && !showCompletionView {
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
        } else if loadedVideoInfo == nil {
            // Placeholder when no video is loaded
            Text("Load a video to start clipping")
                .font(CleanDS.Typography.body)
                .foregroundColor(CleanDS.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(CleanDS.Spacing.lg)
                .cleanSection()
        }
    }
    
    // MARK: - Action Section
    @ViewBuilder
    private var actionSection: some View {
        if showCompletionView, let videoPath = completedVideoPath {
            // Enhanced completion view
            VStack(spacing: CleanDS.Spacing.lg) {
                // Success indicator
                VStack(spacing: CleanDS.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(CleanDS.Colors.success)
                    
                    Text("Clip Complete!")
                        .font(CleanDS.Typography.title)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                }
                
                // Video info with clipped time
                if let videoInfo = loadedVideoInfo {
                    HStack(spacing: CleanDS.Spacing.md) {
                        // Thumbnail
                        AsyncImage(url: URL(string: videoInfo.thumbnailURL ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(CleanDS.Colors.backgroundTertiary)
                        }
                        .frame(width: 60, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: CleanDS.Radius.small))
                        
                        VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                            Text(videoInfo.title)
                                .font(CleanDS.Typography.caption)
                                .foregroundColor(CleanDS.Colors.textPrimary)
                                .lineLimit(1)
                            Text("Clipped: \(startTime) - \(endTime)")
                                .font(CleanDS.Typography.caption)
                                .foregroundColor(CleanDS.Colors.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(CleanDS.Spacing.sm)
                    .background(CleanDS.Colors.backgroundSecondary)
                    .cornerRadius(CleanDS.Radius.small)
                }
                
                // Action buttons
                VStack(spacing: CleanDS.Spacing.sm) {
                    HStack(spacing: CleanDS.Spacing.sm) {
                        CleanActionButton("Open Video", style: .primary) {
                            openVideo(at: videoPath)
                        }
                        
                        CleanActionButton("Show in Finder", style: .secondary) {
                            showInFinder(path: videoPath)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, CleanDS.Spacing.xs)
                    
                    // Continue options
                    HStack(spacing: CleanDS.Spacing.md) {
                        CleanActionButton("Continue with Same Video", style: .secondary) {
                            continueWithSameVideo()
                        }
                        
                        CleanActionButton("New Video", style: .ghost) {
                            resetState()
                        }
                    }
                }
            }
            .cleanSection()
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                removal: .opacity
            ))
        } else if !isProcessing {
            CleanActionButton(
                "Create Clip",
                icon: "scissors",
                style: .primary,
                isDisabled: urlText.isEmpty || loadedVideoInfo == nil,
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
        showCompletionView = false

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
                self.showCompletionView = true
                self.savedVideoURL = urlText
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
        showCompletionView = false
        savedVideoURL = ""
        
        // Cancel any running tasks
        videoInfoLoadingTask?.cancel()
        processingTask?.cancel()
    }
    
    private func continueWithSameVideo() {
        // Keep the same video loaded but reset clip settings
        completedVideoPath = nil
        processingProgress = 0.0
        processingMessage = "Starting..."
        startTime = "00:00:00"
        endTime = "00:00:10"
        showCompletionView = false
        // Keep the loaded video info and URL
        urlText = savedVideoURL
    }
}

#Preview {
    CleanClipperView()
        .environmentObject(BinaryManager())
        .environmentObject(ErrorHandler())
        .environmentObject(LicenseManager.shared)
        .environmentObject(UsageTracker.shared)
}