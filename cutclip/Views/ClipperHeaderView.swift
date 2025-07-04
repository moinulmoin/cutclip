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
            Text("CutClip")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(CleanDS.Colors.textPrimary)

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