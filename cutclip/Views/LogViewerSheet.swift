//
//  LogViewerSheet.swift
//  cutclip
//
//  Created by Moinul Moin on 7/9/25.
//

import SwiftUI
import AppKit

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = "Loading logs..."
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CutClip Logs")
                    .font(.title2.bold())
                
                Spacer()
                
                Button(action: openLogsFolder) {
                    Label("Open in Finder", systemImage: "folder")
                }
                
                Button(action: exportLogs) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            
            Divider()
            
            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("top")
                }
                .background(Color(NSColor.textBackgroundColor))
                .onAppear {
                    loadLogs()
                    // Scroll to bottom on appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("top", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: 800, height: 600)
    }
    
    private func loadLogs() {
        Task {
            let logURL = LoggingService.shared.getLogFileURL()
            do {
                let content = try String(contentsOf: logURL, encoding: .utf8)
                await MainActor.run {
                    logContent = content
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    logContent = "Failed to load logs: \(error.localizedDescription)\n\nLog location: \(logURL.path)"
                    isLoading = false
                }
            }
        }
    }
    
    private func openLogsFolder() {
        let logsDir = LoggingService.shared.getLogFileURL().deletingLastPathComponent()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsDir.path)
    }
    
    private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "cutclip_logs_\(Date().timeIntervalSince1970).txt"
        savePanel.allowedContentTypes = [.plainText]
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try logContent.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    // Show error alert if needed
                }
            }
        }
    }
}