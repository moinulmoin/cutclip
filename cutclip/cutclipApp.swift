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

                    // Initialize license system only once
                    LicenseManager.shared.initializeLicenseSystem()
                }
        }
        .defaultSize(width: DesignSystem.Layout.defaultWindowWidth, height: DesignSystem.Layout.defaultWindowHeight)
        .windowResizability(.contentMinSize)
        .defaultPosition(UnitPoint.center)
    }
}
