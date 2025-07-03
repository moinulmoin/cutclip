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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CutClip")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(CleanDS.Colors.textPrimary)
                
                Text("Create clips from YouTube videos")
                    .font(CleanDS.Typography.caption)
                    .foregroundColor(CleanDS.Colors.textSecondary)
            }
            
            Spacer()
            
            HStack(spacing: CleanDS.Spacing.sm) {
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
        .padding(.horizontal, CleanDS.Spacing.containerNormal)
        .padding(.vertical, CleanDS.Spacing.md)
        .background(
            CleanDS.Colors.backgroundPrimary
                .overlay(
                    Color.white.opacity(0.05)
                )
        )
    }
}