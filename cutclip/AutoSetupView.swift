//
//  AutoSetupView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct AutoSetupView: View {
    @StateObject private var setupService = AutoSetupService()
    @ObservedObject var binaryManager: BinaryManager
    @State private var hasStartedSetup = false
    @State private var animateIcon = false
    @State private var showContent = false
    @State private var setupTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: CleanDS.Spacing.sectionSpacing) {
            // Header Section - only show when not complete
            if !setupService.isSetupComplete {
                VStack(spacing: CleanDS.Spacing.lg) {
                    // Animated App Icon
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: CleanDS.Radius.medium))
                        .scaleEffect(animateIcon ? 1.0 : 0.9)
                        .rotationEffect(.degrees(animateIcon ? 3 : -3))
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animateIcon)
                    .opacity(showContent ? 1.0 : 0.0)
                    .scaleEffect(showContent ? 1.0 : 0.5)
                    .animation(.bouncy(duration: 0.15).delay(0.05), value: showContent)

                    VStack(spacing: CleanDS.Spacing.xs) {
                        Text("Setting up CutClip")
                            .font(CleanDS.Typography.headline)
                            .foregroundColor(CleanDS.Colors.textPrimary)

                        Text("Almost ready to clip some bangers!")
                            .font(CleanDS.Typography.caption)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                    }
                    .opacity(showContent ? 1.0 : 0.0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeInOut(duration: 0.15).delay(0.1), value: showContent)
                }
            }

            // Content Section
            VStack(spacing: CleanDS.Spacing.betweenComponents) {
                if setupService.isSetupComplete {
                    CleanSetupCompleteView {
                        completeSetup()
                    }
                } else if !hasStartedSetup {
                    VStack(spacing: CleanDS.Spacing.md) {
                        Text("CutClip needs to download video processing tools to work properly.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                            .font(CleanDS.Typography.body)

                        Button("Get Started") {
                            startSetup()
                        }
                        .cleanPrimaryButton()
                    }
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.15).delay(0.15), value: showContent)
                } else {
                    CleanSetupProgressView(
                        setupService: setupService,
                        onRetry: startSetup
                    )
                }
            }
            }
        }
        .padding(CleanDS.Spacing.containerNormal)
        .cleanWindow()
        .cleanContent(maxWidth: 400)
        .onAppear {
            animateIcon = true
            showContent = true
        }
        .onDisappear {
            // Cancel setup task if view disappears
            setupTask?.cancel()
        }
    }

    private func startSetup() {
        hasStartedSetup = true
        // Cancel any existing setup task
        setupTask?.cancel()
        
        setupTask = Task {
            await setupService.performAutoSetup()
            setupTask = nil
        }
    }

    private func completeSetup() {
        // Update binary manager with downloaded paths
        // Since AutoSetupService has already verified these binaries work,
        // we can set them directly without additional verification
        let paths = setupService.getBinaryPaths()
        if let ytDlpPath = paths.ytDlp {
            binaryManager.setBinaryPathVerified(for: .ytDlp, path: ytDlpPath)
        }
        if let ffmpegPath = paths.ffmpeg {
            binaryManager.setBinaryPathVerified(for: .ffmpeg, path: ffmpegPath)
        }
        
        // Mark as configured immediately since binaries are pre-verified
        binaryManager.markAsConfigured()
    }
}

// Supporting Views
struct CleanSetupProgressView: View {
    @ObservedObject var setupService: AutoSetupService
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: CleanDS.Spacing.lg) {
            Text(setupService.setupMessage)
                .font(CleanDS.Typography.body)
                .foregroundColor(CleanDS.Colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: CleanDS.Spacing.sm) {
                ProgressView(value: setupService.setupProgress)
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
                    .tint(CleanDS.Colors.accent)

                Text("\(Int(setupService.setupProgress * 100))%")
                    .font(CleanDS.Typography.captionMedium)
                    .foregroundColor(CleanDS.Colors.accent)
            }

            if let error = setupService.setupError {
                VStack(spacing: CleanDS.Spacing.md) {
                    HStack(spacing: CleanDS.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(CleanDS.Colors.error)
                        Text("Setup Error")
                            .font(CleanDS.Typography.bodyMedium)
                            .foregroundColor(CleanDS.Colors.error)
                    }

                    Text(error)
                        .font(CleanDS.Typography.caption)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    CleanActionButton(
                        "Try Again",
                        style: .secondary
                    ) {
                        onRetry()
                    }
                }
                .padding(CleanDS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: CleanDS.Radius.medium)
                        .fill(CleanDS.Colors.error.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: CleanDS.Radius.medium)
                                .stroke(CleanDS.Colors.error.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
        .cleanSection()
    }
}

struct CleanSetupCompleteView: View {
    let onContinue: () -> Void
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: CleanDS.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(CleanDS.Colors.success)
                .scaleEffect(showSuccess ? 1.0 : 0.8)
                .animation(CleanDS.Animation.smooth.delay(0.05), value: showSuccess)

            VStack(spacing: CleanDS.Spacing.xs) {
                Text("Setup Complete")
                    .font(CleanDS.Typography.title)
                    .foregroundColor(CleanDS.Colors.textPrimary)

                Text("Ready to start clipping videos")
                    .font(CleanDS.Typography.caption)
                    .foregroundColor(CleanDS.Colors.textSecondary)
            }
            .opacity(showSuccess ? 1.0 : 0.0)
            .animation(CleanDS.Animation.standard.delay(0.1), value: showSuccess)

            CleanActionButton(
                "Continue",
                style: .primary
            ) {
                onContinue()
            }
            .opacity(showSuccess ? 1.0 : 0.0)
            .animation(CleanDS.Animation.standard.delay(0.15), value: showSuccess)
        }
        .cleanSection()
        .onAppear {
            showSuccess = true
        }
    }
}

#Preview {
    AutoSetupView(binaryManager: BinaryManager())
}