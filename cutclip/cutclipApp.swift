//
//  cutclipApp.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

@main
struct cutclipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
        .defaultSize(width: 500, height: 600)
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem, addition: { })
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appDelegate.checkForUpdates(nil)
                }
                .keyboardShortcut("U", modifiers: [.command])
            }
        }
    }
}
