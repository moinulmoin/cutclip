//
//  ClipperViewModern.swift
//  cutclip
//
//  Created by Moinul Moin on 6/28/25.
//

import SwiftUI

struct ClipperViewModern: View {
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
    private var modernUsageIndicator: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            switch licenseManager.licenseStatus {
            case .licensed:
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(DesignSystem.Colors.success)
                        .font(DesignSystem.Typography.caption)
                    Text("Pro")
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundColor(DesignSystem.Colors.success)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.Colors.success.opacity(0.1))
                .cornerRadius(DesignSystem.CornerRadius.sm)
                
            case .freeTrial(let remaining):
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "gift.fill")
                        .foregroundColor(remaining <= 1 ? DesignSystem.Colors.warning : DesignSystem.Colors.info)
                        .font(DesignSystem.Typography.caption)
                    Text("\(remaining) left")
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundColor(remaining <= 1 ? DesignSystem.Colors.warning : DesignSystem.Colors.info)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background((remaining <= 1 ? DesignSystem.Colors.warning : DesignSystem.Colors.info).opacity(0.1))
                .cornerRadius(DesignSystem.CornerRadius.sm)
                
            case .trialExpired, .unlicensed:
                Button("Get Pro") {
                    showingLicenseView = true
                }
                .font(DesignSystem.Typography.captionBold)
                .foregroundColor(DesignSystem.Colors.textOnPrimary)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.Colors.primary)
                .cornerRadius(DesignSystem.CornerRadius.sm)
                
            case .unknown:
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Modern Header Section
                VStack(spacing: DesignSystem.Spacing.lg) {
                    HStack {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("CutClip")
                                .font(DesignSystem.Typography.largeTitle)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text("Create clips from YouTube videos")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Status & Settings
                        HStack(spacing: DesignSystem.Spacing.md) {
                            modernUsageIndicator
                            
                            Button(action: {
                                showingLicenseView = true
                            }) {
                                Image(systemName: "gearshape.fill")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Settings")
                        }
                    }
                }
                .cardStyle()
                .padding(.bottom, DesignSystem.Spacing.lg)

                // Modern URL Input Section
                VStack(spacing: DesignSystem.Spacing.lg) {
                    ModernInputField(
                        title: "YouTube Video URL", 
                        text: $urlText,
                        placeholder: "https://youtube.com/watch?v=...",
                        isDisabled: isProcessing || isLoadingVideoInfo,
                        onTextChange: { clearVideoInfo() },
                        trailing: {
                            Button(action: loadVideoInfo) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    if isLoadingVideoInfo {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(DesignSystem.Colors.primary)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundColor(DesignSystem.Colors.primary)
                                    }
                                    Text("Load Info")
                                        .font(DesignSystem.Typography.bodyBold)
                                }
                            }
                            .primaryButtonStyle()
                            .disabled(urlText.isEmpty || isProcessing || isLoadingVideoInfo)
                        }
                    )

                    // Modern Video Preview Card
                    if let videoInfo = loadedVideoInfo {
                        ModernVideoPreviewCard(videoInfo: videoInfo)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                    }

                    // Modern Clip Settings Section
                    VStack(spacing: DesignSystem.Spacing.md) {
                        SectionHeader(title: "Clip Settings")
                        
                        HStack(spacing: DesignSystem.Spacing.md) {
                            ModernInputField(
                                title: "Start Time",
                                text: $startTime,
                                placeholder: "00:00:00",
                                isDisabled: isProcessing || isLoadingVideoInfo
                            )
                            
                            ModernInputField(
                                title: "End Time",
                                text: $endTime,
                                placeholder: "00:00:10",
                                isDisabled: isProcessing || isLoadingVideoInfo
                            )
                        }
                        
                        HStack(spacing: DesignSystem.Spacing.md) {
                            ModernStringPickerField(
                                title: "Quality",
                                selection: $selectedQuality,
                                options: qualityOptions,
                                isDisabled: isProcessing || isLoadingVideoInfo
                            )
                            
                            ModernAspectRatioPickerField(
                                title: "Aspect Ratio",
                                selection: $selectedAspectRatio,
                                options: aspectRatioOptions,
                                isDisabled: isProcessing || isLoadingVideoInfo
                            )
                        }
                    }
                    .cardStyle()

                    // Modern Progress Section
                    if isProcessing {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            HStack {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                    Text("Processing Video")
                                        .font(DesignSystem.Typography.bodyBold)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    
                                    Text(processingMessage)
                                        .font(DesignSystem.Typography.body)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                Text("\(Int(processingProgress * 100))%")
                                    .font(DesignSystem.Typography.bodyBold)
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                            
                            ProgressView(value: processingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.Colors.primary))
                                .frame(height: 6)
                        }
                        .cardStyle()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }

                    // Modern Action Section
                    if let videoPath = completedVideoPath {
                        ModernCompletionCard(
                            onOpenVideo: { openVideo(at: videoPath) },
                            onShowInFinder: { showInFinder(path: videoPath) },
                            onNewClip: resetState
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                    } else if !isProcessing {
                        ModernActionButton(
                            title: "Create Clip",
                            icon: "scissors",
                            action: processVideo,
                            isDisabled: urlText.isEmpty
                        )
                        .transition(.opacity)
                    }
                }
                .cardStyle()
            }
        }
        .padding(DesignSystem.Spacing.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentContainerStyle(maxWidth: 700)
        .background(DesignSystem.Colors.backgroundPrimary)
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
        .animation(DesignSystem.Animation.standard, value: loadedVideoInfo?.title)
        .animation(DesignSystem.Animation.standard, value: isProcessing)
        .animation(DesignSystem.Animation.standard, value: completedVideoPath)
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
    ClipperViewModern()
        .environmentObject(BinaryManager())
        .environmentObject(ErrorHandler())
        .environmentObject(LicenseManager.shared)
        .environmentObject(UsageTracker.shared)
}