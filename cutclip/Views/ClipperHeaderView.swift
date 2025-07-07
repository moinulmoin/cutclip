//
//  ClipperHeaderView.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import SwiftUI

struct ClipperHeaderView: View {
    let licenseStatus: LicenseStatus
    let onShowLicense: () -> Void
    let onShowSettings: () -> Void
    @ObservedObject private var usageTracker = UsageTracker.shared

    var body: some View {
        HStack {
            Text("CutClip")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(CleanDS.Colors.textPrimary)

            Spacer()

            HStack(spacing: CleanDS.Spacing.sm) {
                // Daily download counter (shows after 10+ downloads)
                if usageTracker.dailyDownloadCount >= 10 {
                    Text("\(usageTracker.dailyDownloadCount) today")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Status indicator
                CleanStatusIndicator(
                    licenseStatus: licenseStatus,
                    onUpgrade: onShowLicense
                )

                // Settings button
                Button(action: onShowSettings) {
                    Image(systemName: "gearshape")
                        .font(CleanDS.Typography.body)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                }
                .cleanGhostButton()
            }
        }
        .padding(.horizontal, CleanDS.Spacing.md)
        .padding(.vertical, 8)
        .background(
            CleanDS.Colors.backgroundPrimary
                .overlay(
                    Color.white.opacity(0.03)
                )
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}