//
//  DisclaimerView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct DisclaimerView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var showContent = false

    var body: some View {
        ScrollView {
            VStack(spacing: CleanDS.Spacing.sectionSpacing) {
                // Clean Header
                VStack(spacing: CleanDS.Spacing.lg) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: CleanDS.Radius.medium))
                        .scaleEffect(showContent ? 1.0 : 0.8)
                        .animation(CleanDS.Animation.smooth.delay(0.1), value: showContent)
                    
                    VStack(spacing: CleanDS.Spacing.xs) {
                        Text("Welcome to CutClip")
                            .font(CleanDS.Typography.headline)
                            .foregroundColor(CleanDS.Colors.textPrimary)
                        
                        Text("YouTube video clipping made simple")
                            .font(CleanDS.Typography.caption)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                    }
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(CleanDS.Animation.standard.delay(0.2), value: showContent)
                }
                
                // Clean Content
                VStack(spacing: CleanDS.Spacing.betweenComponents) {
                    Text("Before we begin, please note:")
                        .font(CleanDS.Typography.bodyMedium)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                        .opacity(showContent ? 1.0 : 0.0)
                        .animation(CleanDS.Animation.standard.delay(0.3), value: showContent)

                    VStack(spacing: CleanDS.Spacing.md) {
                        CleanDisclaimerPoint(
                            icon: "checkmark.shield.fill",
                            text: "Follow YouTube's Terms of Service",
                            delay: 0.4
                        )
                        
                        CleanDisclaimerPoint(
                            icon: "person.fill.checkmark",
                            text: "Only download content you have permission to use",
                            delay: 0.5
                        )
                        
                        CleanDisclaimerPoint(
                            icon: "heart.fill",
                            text: "Respect creators' rights and use responsibly",
                            delay: 0.6
                        )
                    }
                }

                // Clean Terms Agreement
                Text("By continuing, you agree to our [Terms](https://cutclip.moinulmoin.com/terms) and [Privacy Policy](https://cutclip.moinulmoin.com/privacy)")
                    .font(CleanDS.Typography.caption)
                    .foregroundColor(CleanDS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(CleanDS.Animation.standard.delay(0.7), value: showContent)

                // Clean Accept Button
                CleanActionButton(
                    "I Understand and Accept",
                    style: .primary
                ) {
                    coordinator.acceptDisclaimer()
                }
                .opacity(showContent ? 1.0 : 0.0)
                .animation(CleanDS.Animation.standard.delay(0.8), value: showContent)
            }
        }
        .padding(CleanDS.Spacing.containerNormal)
        .cleanWindow()
        .cleanContent(maxWidth: 400)
        .onAppear {
            showContent = true
        }
    }
}

struct CleanDisclaimerPoint: View {
    let icon: String
    let text: String
    let delay: Double
    @State private var show = false
    
    var body: some View {
        HStack(alignment: .top, spacing: CleanDS.Spacing.sm) {
            Image(systemName: icon)
                .font(CleanDS.Typography.body)
                .foregroundColor(CleanDS.Colors.accent)
                .frame(width: 18)
            
            Text(text)
                .font(CleanDS.Typography.body)
                .foregroundColor(CleanDS.Colors.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .opacity(show ? 1.0 : 0.0)
        .offset(y: show ? 0 : 10)
        .animation(CleanDS.Animation.standard.delay(delay), value: show)
        .onAppear {
            show = true
        }
    }
}

#Preview {
    DisclaimerView()
}