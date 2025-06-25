//
//  ContentView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var binaryManager = BinaryManager()
    @StateObject private var errorHandler = ErrorHandler()
    @StateObject private var licenseManager = LicenseManager.shared
    @StateObject private var usageTracker = UsageTracker.shared
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    // Remove duplicate state - use LicenseManager's state instead

    var body: some View {
        Group {
            if !disclaimerAccepted {
                DisclaimerView()
            } else if !binaryManager.isConfigured {
                AutoSetupView(binaryManager: binaryManager)
            } else if !licenseManager.isInitialized {
                // Show loading while LicenseManager initializes
                VStack {
                    ProgressView("Initializing...")
                        .scaleEffect(1.2)
                }
                .frame(width: 500, height: 450)
            } else if licenseManager.needsLicenseSetup {
                LicenseStatusView()
                    .environmentObject(licenseManager)
                    .environmentObject(usageTracker)
                    .environmentObject(errorHandler)
            } else {
                ClipperView()
                    .environmentObject(binaryManager)
                    .environmentObject(errorHandler)
                    .environmentObject(licenseManager)
                    .environmentObject(usageTracker)
            }
        }
        .errorAlert(errorHandler)
    }
}

#Preview {
    ContentView()
}
