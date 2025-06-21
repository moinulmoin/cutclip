//
//  SetupWizardView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var binaryManager: BinaryManager
    @State private var isVerifying = false
    @State private var verificationMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Binary Setup")
                .font(.title)
            
            Text("CutClip requires yt-dlp and FFmpeg binaries to function. Please locate these on your system.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 15) {
                BinarySelectionRow(
                    title: "yt-dlp",
                    path: binaryManager.ytDlpPath,
                    onSelect: { path in
                        binaryManager.setBinaryPath(for: .ytDlp, path: path)
                    }
                )
                
                BinarySelectionRow(
                    title: "FFmpeg",
                    path: binaryManager.ffmpegPath,
                    onSelect: { path in
                        binaryManager.setBinaryPath(for: .ffmpeg, path: path)
                    }
                )
            }
            
            if binaryManager.isConfigured {
                Button(action: verifyBinaries) {
                    if isVerifying {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Verifying...")
                        }
                    } else {
                        Text("Verify Binaries")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isVerifying)
                
                if !verificationMessage.isEmpty {
                    Text(verificationMessage)
                        .foregroundColor(verificationMessage.contains("Success") ? .green : .red)
                }
            }
            
            Text("Tip: You can install these using Homebrew:\nbrew install yt-dlp ffmpeg")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(width: 500)
    }
    
    private func verifyBinaries() {
        isVerifying = true
        verificationMessage = ""
        
        Task {
            let isValid = await binaryManager.verifyAllBinaries()
            
            await MainActor.run {
                isVerifying = false
                verificationMessage = isValid ? "✅ Success! Both binaries are working correctly." : "❌ Verification failed. Please check your binary paths."
            }
        }
    }
}

struct BinarySelectionRow: View {
    let title: String
    let path: String?
    let onSelect: (String) -> Void
    
    var body: some View {
        HStack {
            Text(title)
                .frame(width: 60, alignment: .leading)
            
            Text(path ?? "Not selected")
                .foregroundColor(path == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Browse") {
                selectBinary()
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func selectBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select \(title) binary"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                onSelect(url.path)
            }
        }
    }
}

#Preview {
    SetupWizardView(binaryManager: BinaryManager())
}