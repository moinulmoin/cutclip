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

    @State private var showingInput = false
    @State private var licenseKeyInput = ""
    @State private var isValidating = false
    @State private var validationError: String? = nil

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)

                Text("CutClip")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("YouTube Video Clipper")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // License Status Section
            VStack(spacing: 16) {
                if licenseManager.isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Checking license status...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Current status display
                    statusDisplay

                    // Action buttons
                    actionButtons

                    // Error display
                    if let error = validationError ?? licenseManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(isPresented: $showingInput) {
            licenseInputSheet
        }
        .onAppear {
            Task {
                await refreshLicenseStatus()
            }
        }
    }

    @ViewBuilder
    private var statusDisplay: some View {
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
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Get License") {
                if let url = URL(string: "https://clipcut.moinulmoin.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)

            Button("Activate") {
                showingInput = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(licenseKeyInput.isEmpty || licenseManager.isLoading)
        }
    }

    @ViewBuilder
    private var licenseInputSheet: some View {
        VStack(spacing: 12) {
            TextField("PRO-XXXXX-XXXXX", text: $licenseKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingInput = false
                }
                .buttonStyle(.bordered)

                Button("Activate") {
                    Task {
                        await validateLicenseKey()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKeyInput.isEmpty || licenseManager.isLoading)
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

    @MainActor
    private func validateLicenseKey() async {
        // Ensure atomic state update at start
        guard !licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationError = "Please enter a license key"
            return
        }

        // Clear previous error and set loading state
        validationError = nil
        isValidating = true

        defer {
            // Ensure loading state is cleared
            isValidating = false
        }

        let success = await licenseManager.validateLicense(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))

        if success {
            // Success - update state atomically
            licenseKeyInput = ""
            showingInput = false
            await refreshLicenseStatus()
        } else {
            // Failure - show error
            validationError = licenseManager.errorMessage ?? "License validation failed"
        }
    }

    @MainActor
    private func refreshLicenseStatus() async {
        await licenseManager.refreshLicenseStatus()
    }
}

#Preview {
    LicenseStatusView()
        .environmentObject(LicenseManager.shared)
        .environmentObject(UsageTracker.shared)
        .environmentObject(ErrorHandler())
}