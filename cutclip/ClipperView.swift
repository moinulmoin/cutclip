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
    @State private var selectedRatio = "Original"
    @AppStorage("bangersClipped") private var bangersCount = 0
    
    @EnvironmentObject private var binaryManager: BinaryManager
    @EnvironmentObject private var errorHandler: ErrorHandler
    
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 20) {
            // URL Input
            HStack {
                TextField("https://www.youtube.com/watch?v=...", text: $urlText)
                    .textFieldStyle(.roundedBorder)

                Button(action: download) {
                    Image(systemName: isProcessing ? "stop.circle.fill" : "arrow.down.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(isProcessing ? .red : .accentColor)
                }
                .disabled(urlText.isEmpty)
            }

            // Time inputs
            HStack {
                VStack(alignment: .leading) {
                    Text("Start At").font(.caption)
                    TextField("00:00:00", text: $startTime)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("End At").font(.caption)
                    TextField("00:00:10", text: $endTime)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("Ratio").font(.caption)
                    Picker("", selection: $selectedRatio) {
                        Text("Original").tag("Original")
                        Text("16:9").tag("16:9")
                        Text("1:1").tag("1:1")
                    }
                }
            }

            // Status
            Text("🔥 \(bangersCount) bangers clipped")
                .foregroundColor(.orange)
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .frame(width: 600, height: 200)
    }
    
    private func download() {
        guard !isProcessing else { return }
        
        Task {
            await performClipWorkflow()
        }
    }
    
    @MainActor
    private func performClipWorkflow() async {
        isProcessing = true
        
        do {
            // Validate inputs
            try ErrorHandler.validateTimeInputs(startTime: startTime, endTime: endTime)
            
            // Check network connectivity
            try await ErrorHandler.checkNetworkConnectivity()
            
            // Check disk space
            try ErrorHandler.checkDiskSpace()
            
            // Create clip job
            let aspectRatio = ClipJob.AspectRatio(rawValue: selectedRatio) ?? .original
            let job = ClipJob(
                url: urlText,
                startTime: startTime,
                endTime: endTime,
                aspectRatio: aspectRatio
            )
            
            // Initialize services with current binary manager
            let downloadSvc = DownloadService(binaryManager: binaryManager)
            let clipSvc = ClipService(binaryManager: binaryManager)
            
            // Download video
            let downloadedPath = try await downloadSvc.downloadVideo(for: job)
            
            // Clip video
            let outputPath = try await clipSvc.clipVideo(inputPath: downloadedPath, job: job)
            
            // Increment counter
            bangersCount += 1
            
            // Show success (you could add a success message here)
            print("Successfully clipped video to: \(outputPath)")
            
        } catch let error as DownloadError {
            errorHandler.handle(error.toAppError())
        } catch let error as ClipError {
            errorHandler.handle(error.toAppError())
        } catch {
            errorHandler.handle(error)
        }
        
        isProcessing = false
    }
}

#Preview {
    ClipperView()
}