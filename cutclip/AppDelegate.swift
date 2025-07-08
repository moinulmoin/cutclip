//
//  AppDelegate.swift
//  cutclip
//
//  Created by Moinul Moin on 7/4/25.
//

import Cocoa
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Shared instance for SwiftUI access
    static private(set) var shared: AppDelegate?
    
    // Sparkle updater controller - lazy initialization to ensure proper setup
    private lazy var updaterController: SPUStandardUpdaterController = {
        print("🚀 AppDelegate: Initializing SPUStandardUpdaterController")
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        print("🚀 AppDelegate: SPUStandardUpdaterController initialized: \(controller)")
        return controller
    }()
    
    override init() {
        super.init()
        AppDelegate.shared = self
        print("🚀 AppDelegate: init called, shared instance set")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sparkle will automatically start checking for updates
        // based on the SUEnableAutomaticChecks setting in Info.plist
        print("🚀 AppDelegate: applicationDidFinishLaunching called")
        print("🚀 AppDelegate: Updater controller initialized: \(updaterController)")
        print("🚀 AppDelegate: Can check for updates: \(canCheckForUpdates)")
        
        // Verify Sparkle configuration
        if let feedURL = updaterController.updater.feedURL {
            print("🚀 AppDelegate: Feed URL: \(feedURL)")
        } else {
            print("⚠️ AppDelegate: No feed URL configured!")
        }
        
        print("🚀 AppDelegate: Automatic checks enabled: \(updaterController.updater.automaticallyChecksForUpdates)")
    }
    
    // Make updater controller accessible for menu actions
    @objc func checkForUpdates(_ sender: Any?) {
        print("🔍 AppDelegate: checkForUpdates called with sender: \(String(describing: sender))")
        print("🔍 AppDelegate: Updater controller: \(updaterController)")
        print("🔍 AppDelegate: Can check for updates: \(canCheckForUpdates)")
        updaterController.checkForUpdates(sender)
    }
    
    // Expose the updater for menu validation
    var canCheckForUpdates: Bool {
        return updaterController.updater.canCheckForUpdates
    }
}