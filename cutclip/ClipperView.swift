//
//  ClipperView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI
import Sparkle

struct ClipperView: View {
    @State private var urlText = ""
    @State private var startTime = "00:00:00"
    @State private var endTime = "00:00:10"
    @State private var selectedQuality = "720p"

    @EnvironmentObject private var binaryManager: BinaryManager
    @EnvironmentObject private var errorHandler: ErrorHandler
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var usageTracker: UsageTracker
    @EnvironmentObject private var updateManager: UpdateManager

    @State private var isProcessing = false
    @State private var processingProgress: Double = 0.0
    @State private var processingMessage = "Starting..."
    @State private var completedVideoPath: String?
    @State private var showingLicenseView = false

    let qualityOptions = ["360p", "480p", "720p", "1080p", "Best"]
    
    @ViewBuilder
    private var usageStatusIndicator: some View {
        HStack(spacing: 8) {
            switch usageTracker.getUsageStatus() {
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
                
            case .trialExpired:
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
                    .buttonStyle(.plain)
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

                    TextField("https://youtube.com/watch?v=...", text: $urlText)
                        .textFieldStyle(MinimalTextFieldStyle())
                        .disabled(isProcessing)
                }

                // Time Settings
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("00:00:00", text: $startTime)
                            .textFieldStyle(MinimalTextFieldStyle())
                            .disabled(isProcessing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("End")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("00:00:10", text: $endTime)
                            .textFieldStyle(MinimalTextFieldStyle())
                            .disabled(isProcessing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quality")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(qualityOptions, id: \.self) { quality in
                                Text(quality).tag(quality)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isProcessing)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    }

    private func processVideo() {
        Task {
            await performClipWorkflow()
        }
    }

    @MainActor
    private func performClipWorkflow() async {
        isProcessing = true
        processingProgress = 0.0
        completedVideoPath = nil

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
            let aspectRatio = ClipJob.AspectRatio.original // Keep original for now
            let job = ClipJob(
                url: urlText,
                startTime: startTime,
                endTime: endTime,
                aspectRatio: aspectRatio
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
            
            // Complete
            processingMessage = "Complete!"
            processingProgress = 1.0
            completedVideoPath = outputPath

        } catch let error as DownloadError {
            errorHandler.handle(error.toAppError())
        } catch let error as ClipError {
            errorHandler.handle(error.toAppError())
        } catch let error as UsageError {
            errorHandler.handle(AppError.licenseError(error.localizedDescription))
        } catch {
            errorHandler.handle(error)
        }

        isProcessing = false
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

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.black, in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ClipperView()
}