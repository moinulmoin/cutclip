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
    @State private var currentView: AppView = .disclaimer
    
    enum AppView {
        case disclaimer
        case autoSetup
        case loading
        case licenseSetup
        case main
    }
    
    var body: some View {
        ZStack {
            // Background
            CleanDS.Colors.backgroundPrimary
                .ignoresSafeArea()
            
            // Content with transitions
            Group {
                switch currentView {
                case .disclaimer:
                    DisclaimerView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 1.05))
                        ))
                case .autoSetup:
                    AutoSetupView(binaryManager: binaryManager)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .loading:
                    VStack(spacing: CleanDS.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Initializing...")
                            .font(CleanDS.Typography.body)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                    }
                    .transition(.opacity)
                case .licenseSetup:
                    LicenseStatusView()
                        .environmentObject(licenseManager)
                        .environmentObject(usageTracker)
                        .environmentObject(errorHandler)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .main:
                    CleanClipperView()
                        .environmentObject(binaryManager)
                        .environmentObject(errorHandler)
                        .environmentObject(licenseManager)
                        .environmentObject(usageTracker)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                }
            }
            .animation(CleanDS.Animation.smooth, value: currentView)
        }
        .errorAlert(errorHandler)
        .onChange(of: disclaimerAccepted) { updateCurrentView() }
        .onChange(of: binaryManager.isConfigured) { updateCurrentView() }
        .onChange(of: licenseManager.isInitialized) { updateCurrentView() }
        .onChange(of: licenseManager.needsLicenseSetup) { updateCurrentView() }
        .onAppear { updateCurrentView() }
    }
    
    private func updateCurrentView() {
        withAnimation(CleanDS.Animation.smooth) {
            if !disclaimerAccepted {
                currentView = .disclaimer
            } else if !binaryManager.isConfigured {
                currentView = .autoSetup
            } else if !licenseManager.isInitialized {
                currentView = .loading
            } else if licenseManager.needsLicenseSetup {
                currentView = .licenseSetup
            } else {
                currentView = .main
            }
        }
    }
}

#Preview {
    ContentView()
}
