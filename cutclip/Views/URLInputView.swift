//
//  URLInputView.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import SwiftUI

struct URLInputView: View {
    @Binding var urlText: String
    let loadedVideoInfo: VideoInfo?
    let isProcessing: Bool
    let isLoadingVideoInfo: Bool
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
                .disabled(urlText.isEmpty || isProcessing || isLoadingVideoInfo)
            }
        } else {
            // Compact URL display when video is loaded
            VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                CleanLabel(text: "YouTube Video URL")
                
                HStack(spacing: CleanDS.Spacing.md) {
                    HStack(spacing: CleanDS.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(CleanDS.Colors.success)
                            .font(CleanDS.Typography.body)
                        
                        Text(urlText)
                            .font(CleanDS.Typography.body)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    CleanActionButton("Change", style: .secondary) {
                        onClearVideoInfo()
                        urlText = ""
                    }
                    .disabled(isProcessing)
                }
                .padding(CleanDS.Spacing.md)
                .background(CleanDS.Colors.backgroundSecondary)
                .cornerRadius(CleanDS.Radius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: CleanDS.Radius.medium)
                        .stroke(CleanDS.Colors.borderLight, lineWidth: 1)
                )
            }
        }
    }
}