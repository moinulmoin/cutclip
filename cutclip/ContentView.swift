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
    @StateObject private var updateManager = UpdateManager.shared
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    
    var body: some View {
        Group {
            if !disclaimerAccepted {
                DisclaimerView()
            } else if !binaryManager.isConfigured {
                AutoSetupView(binaryManager: binaryManager)
            } else if licenseManager.needsLicenseSetup {
                LicenseStatusView()
                    .environmentObject(licenseManager)
                    .environmentObject(usageTracker)
                    .environmentObject(errorHandler)
                    .environmentObject(updateManager)
            } else {
                ClipperView()
                    .environmentObject(binaryManager)
                    .environmentObject(errorHandler)
                    .environmentObject(licenseManager)
                    .environmentObject(usageTracker)
                    .environmentObject(updateManager)
            }
        }
        .errorAlert(errorHandler)
    }
}

#Preview {
    ContentView()
}
