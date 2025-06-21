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
    
    var body: some View {
        VStack(spacing: 30) {
            // App Icon/Logo Area
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            VStack(spacing: 15) {
                Text("Setting up CutClip")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if !hasStartedSetup {
                    Text("CutClip needs to download video processing tools to work properly.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                } else {
                    Text(setupService.setupMessage)
                        .foregroundColor(.secondary)
                }
            }
            
            if !hasStartedSetup {
                Button("Get Started") {
                    startSetup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                VStack(spacing: 15) {
                    ProgressView(value: setupService.setupProgress)
                        .frame(width: 300)
                    
                    if let error = setupService.setupError {
                        VStack(spacing: 10) {
                            Text("Setup Error")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                startSetup()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            
            if setupService.isSetupComplete {
                VStack(spacing: 15) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    
                    Text("All set! 🎉")
                        .font(.headline)
                    
                    Button("Continue") {
                        completeSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
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

#Preview {
    AutoSetupView(binaryManager: BinaryManager())
}