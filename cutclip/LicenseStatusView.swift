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
    
    @State private var licenseKey = ""
    @State private var showingLicenseEntry = false
    
    var body: some View {
        VStack(spacing: 20) {
            // App Logo/Title
            VStack(spacing: 8) {
                Image(systemName: "scissors.badge.ellipsis")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("CutClip")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            // License Status Card
            VStack(spacing: 16) {
                statusCard
                
                if case .trialExpired = usageTracker.getUsageStatus() {
                    licenseEntrySection
                } else {
                    continueButton
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
        }
        .padding(40)
        .task {
            await licenseManager.refreshLicenseStatus()
        }
    }
    
    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            if case .freeTrial(let remaining) = usageTracker.getUsageStatus() {
                HStack {
                    Text("Remaining Uses:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(remaining)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(remaining <= 1 ? .orange : .primary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter License Key")
                    .font(.headline)
                
                TextField("PRO-XXXXX-XXXXX", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            
            HStack(spacing: 12) {
                Button("Get License") {
                    if let url = URL(string: "https://your-website.com/license") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Activate License") {
                    Task {
                        await activateLicense()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKey.isEmpty || licenseManager.isLoading)
            }
            
            if licenseManager.isLoading {
                ProgressView("Validating license...")
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(NSColor.separatorColor).opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var continueButton: some View {
        Button("Continue") {
            licenseManager.needsLicenseSetup = false
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
    
    private func activateLicense() async {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = await licenseManager.activateLicense(trimmedKey)
        
        if success {
            licenseKey = ""
        }
    }
}

#Preview {
    LicenseStatusView()
        .environmentObject(LicenseManager.shared)
        .environmentObject(UsageTracker.shared)
        .environmentObject(ErrorHandler())
}