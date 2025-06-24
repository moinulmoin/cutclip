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

    var body: some View {
        VStack(spacing: 40) {
            // Header Section - only show when not complete
            if !setupService.isSetupComplete {
                VStack(spacing: 20) {
                    // Animated App Icon
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .scaleEffect(animateIcon ? 1.0 : 0.9)
                        .rotationEffect(.degrees(animateIcon ? 3 : -3))
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateIcon)
                    .opacity(showContent ? 1.0 : 0.0)
                    .scaleEffect(showContent ? 1.0 : 0.5)
                    .animation(.bouncy(duration: 0.8).delay(0.2), value: showContent)

                    VStack(spacing: 8) {
                        Text("Setting up CutClip")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("Almost ready to clip some bangers!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(showContent ? 1.0 : 0.0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeInOut(duration: 0.6).delay(0.4), value: showContent)
                }
            }

            // Content Section
            VStack(spacing: 24) {
                if setupService.isSetupComplete {
                    SetupCompleteView {
                        completeSetup()
                    }
                } else if !hasStartedSetup {
                    VStack(spacing: 16) {
                        Text("CutClip needs to download video processing tools to work properly.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        Button("Get Started") {
                            startSetup()
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [.black.opacity(0.8), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .buttonStyle(.plain)
                    }
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.6).delay(0.6), value: showContent)
                } else {
                    SetupProgressView(
                        setupService: setupService,
                        onRetry: startSetup
                    )
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 450)
        .onAppear {
            animateIcon = true
            showContent = true
        }
    }

    private func startSetup() {
        hasStartedSetup = true
        Task {
            await setupService.performAutoSetup()
        }
    }

    private func completeSetup() {
        // Update binary manager with downloaded paths
        let paths = setupService.getBinaryPaths()
        if let ytDlpPath = paths.ytDlp {
            binaryManager.setBinaryPath(for: .ytDlp, path: ytDlpPath)
        }
        if let ffmpegPath = paths.ffmpeg {
            binaryManager.setBinaryPath(for: .ffmpeg, path: ffmpegPath)
        }
    }
}

// Supporting Views
struct SetupProgressView: View {
    @ObservedObject var setupService: AutoSetupService
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(setupService.setupMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ProgressView(value: setupService.setupProgress)
                    .frame(width: 320)
                    .tint(.black)

                Text("\(Int(setupService.setupProgress * 100))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let error = setupService.setupError {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Setup Error")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.red)
                    }

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        onRetry()
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.black, lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.red.opacity(0.05))
                        .strokeBorder(.red.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
}

struct SetupCompleteView: View {
    let onContinue: () -> Void
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(LinearGradient(colors: [.green.opacity(0.8), .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(showSuccess ? 1.0 : 0.5)
                .animation(.bouncy(duration: 0.8), value: showSuccess)

            VStack(spacing: 8) {
                Text("All set!")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Ready to start clipping!")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .opacity(showSuccess ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(0.3), value: showSuccess)

            Button("Continue") {
                onContinue()
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.green.opacity(0.8), .green], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .buttonStyle(.plain)
            .opacity(showSuccess ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(0.6), value: showSuccess)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            showSuccess = true
        }
    }
}

#Preview {
    AutoSetupView(binaryManager: BinaryManager())
}