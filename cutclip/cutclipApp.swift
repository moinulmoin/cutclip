//
//  cutclipApp.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

@main
struct cutclipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if DEBUG
                    // Debug: Verify environment variables
                    print("🔧 API Base URL: \(ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] ?? "not set")")
                    #endif
                    
                    // Initialize license and usage tracking system
                    Task {
                        await initializeLicenseSystem()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
    
    private func initializeLicenseSystem() async {
        // Initialize usage tracking first, then refresh license status
        do {
            let _ = try await UsageTracker.shared.initializeApp()
            print("✅ Usage tracking initialized")
            
            // Only refresh license status after usage tracking completes
            await LicenseManager.shared.refreshLicenseStatus()
            print("✅ License system fully initialized")
        } catch {
            print("❌ Failed to initialize license system: \(error)")
        }
    }
}
