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

    @State private var licenseKeyInput = ""
    @State private var isValidating = false
    @State private var validationError: String? = nil
    @State private var validationTask: Task<Void, Never>?

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
            VStack(spacing: 20) {
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

                    // License Input and Activation
                    VStack(spacing: 12) {
                        TextField("Enter your license key", text: $licenseKeyInput)
                            .textFieldStyle(MinimalTextFieldStyle())
                            .multilineTextAlignment(.center)

                        Button(action: {
                            validationTask?.cancel()
                            validationTask = Task {
                                await validateLicenseKey()
                                validationTask = nil
                            }
                        }) {
                            if isValidating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Text("Activate License")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(licenseKeyInput.isEmpty || isValidating)
                    }

                    // Error display
                    if let error = validationError ?? licenseManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Action buttons
                    actionButtons
                }
            }
        }
        .padding()
        .frame(width: 420, height: 450)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(alignment: .topTrailing) {
            // Explicit Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary, .tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .padding()
        }
        .onAppear {
            validationTask?.cancel()
            validationTask = Task {
                await refreshLicenseStatus()
                validationTask = nil
            }
        }
        .onDisappear {
            validationTask?.cancel()
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
        VStack(spacing: 8) {
            Text("Don't have a license?")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Get Pro License - $4.99") {
                if let url = URL(string: "https://cutclip.moinulmoin.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }

    @MainActor
    private func validateLicenseKey() async {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure atomic state update at start
        guard !key.isEmpty else {
            validationError = "Please enter a license key."
            return
        }

        // Perform basic client-side validation
        guard ValidationUtils.isValidLicenseKeyFormat(key) else {
            validationError = "License can only contain letters, numbers, and hyphens."
            return
        }

        // Clear previous error and set loading state
        validationError = nil
        isValidating = true

        defer {
            // Ensure loading state is cleared
            isValidating = false
        }

        let success = await licenseManager.validateLicense(key)

        if success {
            // Success - update state atomically
            licenseKeyInput = ""
            await refreshLicenseStatus()
            // Optional: dismiss the view if it's a sheet
            // dismiss()
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