//
//  LicenseStatusView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct LicenseStatusView: View {
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var usageTracker: UsageTracker
    @EnvironmentObject private var errorHandler: ErrorHandler
    @Environment(\.dismiss) private var dismiss

    @State private var licenseKey = ""
    @State private var showingLicenseEntry = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
            // Header with close button
            HStack {
                Text("Settings")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            // Status section
            VStack(alignment: .leading, spacing: 12) {
                Text("Status")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                statusCard
            }

            // License section
            VStack(alignment: .leading, spacing: 12) {
                Text("License")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                licenseEntrySection
            }
            
            // Updates section - TODO: Enable in v1.1
            // VStack(alignment: .leading, spacing: 12) {
            //     Button("Check for Updates") {
            //         updateManager.checkForUpdates()
            //     }
            //     .buttonStyle(.plain)
            //     .foregroundColor(.accentColor)
            // }
            }
        }
        .padding(24)
        .frame(width: 440, height: 400)
        .task {
            await licenseManager.refreshLicenseStatus()
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(statusTitle)
                .font(.callout)
                .fontWeight(.medium)

            if case .freeTrial(let remaining) = usageTracker.getUsageStatus() {
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(remaining) uses left")
                    .font(.callout)
                    .foregroundColor(remaining <= 1 ? .orange : .secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch usageTracker.getUsageStatus() {
        case .licensed:
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.title2)
        case .freeTrial:
            Image(systemName: "gift.fill")
                .foregroundColor(.blue)
                .font(.title2)
        case .trialExpired:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
        }
    }

    private var statusTitle: String {
        switch usageTracker.getUsageStatus() {
        case .licensed:
            return "Licensed"
        case .freeTrial:
            return "Free Trial"
        case .trialExpired:
            return "Trial Expired"
        }
    }

    private var statusMessage: String {
        switch usageTracker.getUsageStatus() {
        case .licensed:
            return "Unlimited video processing"
        case .freeTrial(let remaining):
            return remaining <= 1 ? "Almost out of free uses" : "Limited free uses available"
        case .trialExpired:
            return "License required to continue"
        }
    }

    @ViewBuilder
    private var licenseEntrySection: some View {
        VStack(spacing: 12) {
            TextField("PRO-XXXXX-XXXXX", text: $licenseKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack(spacing: 12) {
                Button("Get License") {
                    if let url = URL(string: "https://clipcut.moinulmoin.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button("Activate") {
                    Task {
                        await activateLicense()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKey.isEmpty || licenseManager.isLoading)
            }

            if licenseManager.isLoading {
                ProgressView("Validating...")
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func activateLicense() async {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = await licenseManager.activateLicense(trimmedKey)

        if success {
            licenseKey = ""
            dismiss()
        }
    }
}

#Preview {
    LicenseStatusView()
        .environmentObject(LicenseManager.shared)
        .environmentObject(UsageTracker.shared)
        .environmentObject(ErrorHandler())
}