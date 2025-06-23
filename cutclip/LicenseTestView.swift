//
//  LicenseTestView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct LicenseTestView: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @StateObject private var usageTracker = UsageTracker.shared

    @State private var testLicenseKey = ""
    @State private var showDebugInfo = false

    var body: some View {
        VStack(spacing: 20) {
            Text("🔐 License System Test")
                .font(.title.weight(.bold))

            // Current Status
            VStack(spacing: 12) {
                Text("Current Status")
                    .font(.headline)

                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)

                    Text(licenseManager.licenseStatus.displayText)
                        .font(.callout)
                }

                if usageTracker.getRemainingCredits() >= 0 {
                    Text("Remaining credits: \(usageTracker.getRemainingCredits())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Divider()

            // License Testing
            VStack(spacing: 16) {
                Text("Test License Activation")
                    .font(.headline)

                HStack {
                    TextField("Enter license key", text: $testLicenseKey)
                        .textFieldStyle(.roundedBorder)

                    Button("Validate") {
                        Task {
                            await licenseManager.validateLicense(testLicenseKey)
                        }
                    }
                    .disabled(testLicenseKey.isEmpty || licenseManager.isLoading)
                }

                // Mock license keys
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mock License Keys:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(licenseManager.getMockLicenseKeys(), id: \.self) { key in
                        Button(key) {
                            testLicenseKey = key
                        }
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    }
                }
            }

            // Usage Testing
            VStack(spacing: 12) {
                Text("Test App Usage")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button("Use App") {
                        if licenseManager.canUseApp() {
                            licenseManager.recordAppUsage()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!licenseManager.canUseApp())

                    Button("Check Status") {
                        Task {
                            await licenseManager.refreshLicenseStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            // System Actions
            VStack(spacing: 12) {
                Text("System Actions")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button("Refresh Status") {
                        Task {
                            await licenseManager.refreshLicenseStatus()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Deactivate License") {
                        licenseManager.deactivateLicense()
                    }
                    .buttonStyle(.bordered)

                    Button("Reset All") {
                        licenseManager.resetForTesting()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }

            // Debug Info
            VStack {
                Button("Toggle Debug Info") {
                    showDebugInfo.toggle()
                }
                .font(.caption)

                if showDebugInfo {
                    ScrollView {
                        Text(debugInfoText)
                            .font(.caption.monospaced())
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxHeight: 200)
                }
            }

            // Error Display
            if let error = licenseManager.errorMessage {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Loading Indicator
            if licenseManager.isLoading {
                ProgressView("Processing...")
                    .padding()
            }
        }
        .padding(20)
        .frame(width: 500, height: 700)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusColor: Color {
        switch licenseManager.licenseStatus {
        case .licensed:
            return .green
        case .freeTrial:
            return .orange
        case .trialExpired, .unlicensed:
            return .red
        case .unknown:
            return .gray
        }
    }

    private var debugInfoText: String {
        let debugInfo = licenseManager.getDebugInfo()

        var text = ""
        for (key, value) in debugInfo {
            text += "\(key): \(value)\n"
        }
        return text
    }
}

#Preview {
    LicenseTestView()
}