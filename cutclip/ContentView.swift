//
//  ContentView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some View {
        ZStack {
            // Background
            CleanDS.Colors.backgroundPrimary
                .ignoresSafeArea()
            
            // Content with transitions
            Group {
                switch coordinator.currentView {
                case .disclaimer:
                    DisclaimerView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 1.05))
                        ))
                case .autoSetup:
                    AutoSetupView(binaryManager: coordinator.binaryManager)
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
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .main:
                    CleanClipperView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                }
            }
            .animation(CleanDS.Animation.smooth, value: coordinator.currentView)
            
            // Network status overlay
            if !coordinator.networkMonitor.isConnected {
                VStack {
                    HStack(spacing: CleanDS.Spacing.sm) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 14))
                        Text("No Internet Connection")
                            .font(CleanDS.Typography.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, CleanDS.Spacing.md)
                    .padding(.vertical, CleanDS.Spacing.sm)
                    .background(Color.red)
                    .cornerRadius(CleanDS.Radius.small)
                    .shadow(radius: 4)
                    
                    Spacer()
                }
                .padding(.top, CleanDS.Spacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(CleanDS.Animation.smooth, value: coordinator.networkMonitor.isConnected)
            }
        }
        .frame(minWidth: 450, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .environmentAppCoordinator(coordinator)
        .errorAlert(coordinator.errorHandler)
        .onChange(of: coordinator.binaryManager.isConfigured) { 
            coordinator.updateAppState() 
        }
        .onChange(of: coordinator.licenseManager.isInitialized) { 
            coordinator.updateAppState() 
        }
        .onChange(of: coordinator.licenseManager.needsLicenseSetup) { 
            coordinator.updateAppState() 
        }
    }
}

#Preview {
    ContentView()
}
