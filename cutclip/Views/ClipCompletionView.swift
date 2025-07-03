//
//  ClipCompletionView.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import SwiftUI

struct ClipCompletionView: View {
    let videoPath: String
    let videoInfo: VideoInfo?
    let startTime: String
    let endTime: String
    let onOpenVideo: () -> Void
    let onShowInFinder: () -> Void
    let onContinueWithSameVideo: () -> Void
    let onNewVideo: () -> Void
    
    var body: some View {
        VStack(spacing: CleanDS.Spacing.lg) {
            // Success indicator
            successHeader
            
            // Video info with clipped time
            if let videoInfo = videoInfo {
                videoInfoCard(videoInfo: videoInfo)
            }
            
            // Action buttons
            actionButtons
        }
        .cleanSection()
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98)),
            removal: .opacity
        ))
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private var successHeader: some View {
        VStack(spacing: CleanDS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(CleanDS.Colors.success)
            
            Text("Clip Complete!")
                .font(CleanDS.Typography.title)
                .foregroundColor(CleanDS.Colors.textPrimary)
        }
    }
    
    @ViewBuilder
    private func videoInfoCard(videoInfo: VideoInfo) -> some View {
        HStack(spacing: CleanDS.Spacing.md) {
            // Thumbnail
            AsyncImage(url: URL(string: videoInfo.thumbnailURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(CleanDS.Colors.backgroundTertiary)
            }
            .frame(width: 60, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: CleanDS.Radius.small))
            
            VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                Text(videoInfo.title)
                    .font(CleanDS.Typography.caption)
                    .foregroundColor(CleanDS.Colors.textPrimary)
                    .lineLimit(1)
                Text("Clipped: \(startTime) - \(endTime)")
                    .font(CleanDS.Typography.caption)
                    .foregroundColor(CleanDS.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(CleanDS.Spacing.sm)
        .background(CleanDS.Colors.backgroundSecondary)
        .cornerRadius(CleanDS.Radius.small)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: CleanDS.Spacing.sm) {
            HStack(spacing: CleanDS.Spacing.sm) {
                CleanActionButton("Open Video", style: .primary) {
                    onOpenVideo()
                }
                
                CleanActionButton("Show in Finder", style: .secondary) {
                    onShowInFinder()
                }
            }
            
            Divider()
                .padding(.vertical, CleanDS.Spacing.xs)
            
            // Continue options
            HStack(spacing: CleanDS.Spacing.md) {
                CleanActionButton("Continue with Same Video", style: .secondary) {
                    onContinueWithSameVideo()
                }
                
                CleanActionButton("New Video", style: .ghost) {
                    onNewVideo()
                }
            }
        }
    }
}