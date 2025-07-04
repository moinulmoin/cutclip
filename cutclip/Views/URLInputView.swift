//
//  URLInputView.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import SwiftUI

struct URLInputView: View {
    @Binding var urlText: String
    let urlValidationError: String?
    let loadedVideoInfo: VideoInfo?
    let isProcessing: Bool
    let isLoadingVideoInfo: Bool
    let canLoadVideoInfo: Bool
    let onLoadVideoInfo: () -> Void
    let onClearVideoInfo: () -> Void
    let onTextChange: () -> Void

    var body: some View {
        if loadedVideoInfo == nil {
            // Full URL input when no video is loaded
            CleanInputWithAction(
                label: "YouTube Video URL",
                text: $urlText,
                placeholder: "https://youtube.com/watch?v=...",
                isDisabled: isProcessing || isLoadingVideoInfo,
                errorMessage: urlValidationError,
                onTextChange: onTextChange
            ) {
                Button(action: onLoadVideoInfo) {
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
                .disabled(!canLoadVideoInfo)
            }
        } else {
            // Return empty view when video is loaded
            EmptyView()
        }
    }
}