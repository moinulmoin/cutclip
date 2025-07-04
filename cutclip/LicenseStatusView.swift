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
        VStack(spacing: 0) {
            // Clean Header - Full Width
            HStack(spacing: CleanDS.Spacing.sm) {
                Spacer()

                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: CleanDS.Radius.small))

                Text("CutClip")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(CleanDS.Colors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, CleanDS.Spacing.containerNormal)
            .padding(.vertical, CleanDS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                CleanDS.Colors.backgroundPrimary
                    .overlay(
                        Color.white.opacity(0.05)
                    )
            )

            // Main Content - Constrained Width
            ScrollView {
                VStack(spacing: CleanDS.Spacing.sectionSpacing) {
                    // License Status Section
                    VStack(spacing: CleanDS.Spacing.betweenComponents) {
                        if licenseManager.isLoading {
                            VStack(spacing: CleanDS.Spacing.sm) {
                                ProgressView()
                                    .scaleEffect(1.0)
                                    .tint(CleanDS.Colors.accent)
                                Text("Checking license status...")
                                    .font(CleanDS.Typography.body)
                                    .foregroundColor(CleanDS.Colors.textSecondary)
                            }
                            .cleanSection()
                        } else {
                            // Current status display
                            statusDisplay

                            // License Input and Activation
                            VStack(spacing: CleanDS.Spacing.md) {
                                CleanSectionHeader(title: "Activate License")

                                CleanInputField(
                                    label: "License Key",
                                    text: $licenseKeyInput,
                                    placeholder: "Enter your license key",
                                    isDisabled: isValidating
                                )

                                CleanActionButton(
                                    isValidating ? "Validating..." : "Activate License",
                                    icon: isValidating ? "" : "key.fill",
                                    style: .primary,
                                    isDisabled: licenseKeyInput.isEmpty || isValidating
                                ) {
                                    validationTask?.cancel()
                                    validationTask = Task {
                                        await validateLicenseKey()
                                        validationTask = nil
                                    }
                                }
                            }
                            .cleanSection()

                            // Error display
                            if let error = validationError ?? licenseManager.errorMessage {
                                HStack(spacing: CleanDS.Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(CleanDS.Colors.error)
                                    Text(error)
                                        .font(CleanDS.Typography.caption)
                                        .foregroundColor(CleanDS.Colors.error)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(CleanDS.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: CleanDS.Radius.medium)
                                        .fill(CleanDS.Colors.error.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: CleanDS.Radius.medium)
                                                .stroke(CleanDS.Colors.error.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }

                            // Action buttons
                            actionButtons
                        }
                    }
                }
                .padding(CleanDS.Spacing.containerNormal)
                .frame(minWidth: 400, idealWidth: 420, maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
        }
        .cleanWindow()
        .overlay(alignment: .topTrailing) {
            // Clean close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(CleanDS.Typography.body)
                    .foregroundColor(CleanDS.Colors.textSecondary)
            }
            .cleanGhostButton()
            .keyboardShortcut(.escape, modifiers: [])
            .padding(CleanDS.Spacing.md)
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
        VStack(spacing: CleanDS.Spacing.md) {
            CleanSectionHeader(title: "Current Status")

            HStack(spacing: CleanDS.Spacing.sm) {
                statusIcon

                VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                    Text(statusTitle)
                        .font(CleanDS.Typography.bodyMedium)
                        .foregroundColor(CleanDS.Colors.textPrimary)

                    Text(statusMessage)
                        .font(CleanDS.Typography.caption)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                }

                Spacer()

                if case .freeTrial(let remaining) = usageTracker.getUsageStatus() {
                    CleanStatusBadge(
                        text: "\(remaining) left",
                        color: remaining <= 1 ? CleanDS.Colors.warning : CleanDS.Colors.info
                    )
                }
            }
        }
        .cleanSection()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch usageTracker.getUsageStatus() {
        case .licensed:
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(CleanDS.Colors.success)
                .font(CleanDS.Typography.title)
        case .freeTrial:
            Image(systemName: "gift.fill")
                .foregroundColor(CleanDS.Colors.info)
                .font(CleanDS.Typography.title)
        case .trialExpired:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(CleanDS.Colors.warning)
                .font(CleanDS.Typography.title)
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
            return remaining <= 1 ? "Last free clip! Upgrade now" : "\(remaining) free clips"
        case .trialExpired:
            return "License required to continue"
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: CleanDS.Spacing.md) {
            CleanSectionHeader(title: "Get Lifetime License")

            VStack(spacing: CleanDS.Spacing.sm) {
                VStack(spacing: CleanDS.Spacing.xs) {
                    Text("Create Unlimited Clips")
                        .font(CleanDS.Typography.bodyMedium)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                    Text("One-time purchase • No subscriptions")
                        .font(CleanDS.Typography.caption)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)

                CleanActionButton(
                    "Get Lifetime Access - $4.99",
                    icon: "crown.fill",
                    style: .secondary
                ) {
                    if let url = URL(string: "https://cutclip.moinulmoin.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .cleanSection()
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