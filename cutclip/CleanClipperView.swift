//
//  CleanClipperView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/28/25.
//

import SwiftUI

struct CleanClipperView: View {
    @EnvironmentObject private var binaryManager: BinaryManager
    @EnvironmentObject private var errorHandler: ErrorHandler
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var usageTracker: UsageTracker
    
    @StateObject private var viewModel: ClipperViewModel
    
    init() {
        // Create a temporary view model that will be properly initialized in onAppear
        _viewModel = StateObject(wrappedValue: ClipperViewModel(
            binaryManager: BinaryManager(),
            errorHandler: ErrorHandler(),
            licenseManager: LicenseManager.shared,
            usageTracker: UsageTracker.shared
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sticky Minimal Header
            ClipperHeaderView(
                licenseStatus: licenseManager.licenseStatus,
                onShowLicense: viewModel.showLicenseView,
                onShowSettings: viewModel.showLicenseView
            )
            
            ScrollView {
                // Main Content - Constrained Width
                VStack(spacing: CleanDS.Spacing.sectionSpacing) {
                    // URL Input Section
                    URLInputView(
                        urlText: $viewModel.urlText,
                        urlValidationError: viewModel.urlValidationError,
                        loadedVideoInfo: viewModel.loadedVideoInfo,
                        isProcessing: viewModel.isProcessing,
                        isLoadingVideoInfo: viewModel.isLoadingVideoInfo,
                        canLoadVideoInfo: viewModel.canLoadVideoInfo,
                        onLoadVideoInfo: viewModel.loadVideoInfo,
                        onClearVideoInfo: viewModel.resetState,
                        onTextChange: viewModel.onURLChange
                    )
                    
                    // Video Preview (if loaded) - stays visible through all states
                    if let videoInfo = viewModel.loadedVideoInfo {
                        CleanVideoPreview(
                            videoInfo: videoInfo,
                            onChangeVideo: viewModel.resetState,
                            isChangeDisabled: viewModel.isProcessing
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                    
                    // Clip Settings Section (hidden during completion)
                    if viewModel.hasLoadedVideo && !viewModel.showCompletionView {
                        ClipSettingsView(
                            startTime: $viewModel.startTime,
                            endTime: $viewModel.endTime,
                            selectedQuality: $viewModel.selectedQuality,
                            selectedAspectRatio: $viewModel.selectedAspectRatio,
                            qualityOptions: viewModel.qualityOptions,
                            aspectRatioOptions: viewModel.aspectRatioOptions,
                            isDisabled: viewModel.isProcessing || viewModel.isLoadingVideoInfo
                        )
                    } else if !viewModel.hasLoadedVideo {
                        placeholderView
                    }
                    
                    // Progress Section (if processing)
                    if viewModel.isProcessing && !viewModel.showCompletionView {
                        CleanProgressSection(
                            title: "Processing Video",
                            message: viewModel.processingMessage,
                            progress: viewModel.processingProgress,
                            onCancel: viewModel.cancelProcessing
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
                .cleanContent(maxWidth: 500)
            }
        }
        .cleanWindow()
        .sheet(isPresented: $viewModel.showingLicenseView) {
            LicenseStatusView()
                .environmentObject(licenseManager)
                .environmentObject(usageTracker)
                .environmentObject(errorHandler)
        }
        .onAppear {
            // Update viewModel with actual environment objects
            viewModel.updateDependencies(
                binaryManager: binaryManager,
                errorHandler: errorHandler,
                licenseManager: licenseManager,
                usageTracker: usageTracker
            )
            // Initialize the video info service with the proper binary manager
            viewModel.setupVideoInfoService()
        }
        .animation(CleanDS.Animation.standard, value: viewModel.loadedVideoInfo?.title)
        .animation(CleanDS.Animation.standard, value: viewModel.isProcessing)
        .animation(CleanDS.Animation.standard, value: viewModel.completedVideoPath)
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var placeholderView: some View {
        Text("Load a video to start clipping")
            .font(CleanDS.Typography.body)
            .foregroundColor(CleanDS.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, CleanDS.Spacing.md)
    }
    
    @ViewBuilder
    private var actionSection: some View {
        let _ = print("🎬 ActionSection - showCompletionView: \(viewModel.showCompletionView), completedPath: \(viewModel.completedVideoPath ?? "nil"), isProcessing: \(viewModel.isProcessing)")
        if viewModel.showCompletionView, let videoPath = viewModel.completedVideoPath {
            // Enhanced completion view
            ClipCompletionView(
                videoPath: videoPath,
                videoInfo: viewModel.loadedVideoInfo,
                startTime: viewModel.startTime,
                endTime: viewModel.endTime,
                onOpenVideo: { viewModel.openVideo(at: videoPath) },
                onShowInFinder: { viewModel.showInFinder(path: videoPath) },
                onContinueWithSameVideo: viewModel.continueWithSameVideo,
                onNewVideo: viewModel.resetState
            )
        } else if !viewModel.isProcessing && viewModel.hasLoadedVideo {
            CleanActionButton(
                "Create Clip",
                icon: "scissors",
                style: .primary,
                isDisabled: !viewModel.canCreateClip,
                action: viewModel.processVideo
            )
            .transition(.opacity)
        }
    }
}

// MARK: - Preview

#Preview {
    CleanClipperView()
        .environmentObject(BinaryManager())
        .environmentObject(ErrorHandler())
        .environmentObject(LicenseManager.shared)
        .environmentObject(UsageTracker.shared)
}