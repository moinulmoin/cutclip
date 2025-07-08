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
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.white)
                        }
                        Text("Load")
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(LoadInfoButtonStyle(isEnabled: canLoadVideoInfo))
            }
        } else {
            // Return empty view when video is loaded
            EmptyView()
        }
    }
}

// MARK: - Custom Button Style

private struct LoadInfoButtonStyle: ButtonStyle {
    let isEnabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CleanDS.Typography.bodyMedium)
            .padding(.horizontal, CleanDS.Spacing.md)
            .padding(.vertical, CleanDS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CleanDS.Radius.small)
                    .fill(CleanDS.Colors.accent)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1.0)
            .opacity(configuration.isPressed && isEnabled ? 0.9 : 1.0)
            .animation(CleanDS.Animation.quick, value: configuration.isPressed)
            .allowsHitTesting(isEnabled)
            .opacity(isEnabled ? 1.0 : 0.7)
    }
}