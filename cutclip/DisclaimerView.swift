//
//  DisclaimerView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct DisclaimerView: View {
    @AppStorage("disclaimerAccepted") private var accepted = false
    @State private var showContent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
            // Header
            VStack(spacing: 20) {
                Image("AppLogo")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(showContent ? 1.0 : 0.5)
                    .animation(.bouncy(duration: 0.8).delay(0.2), value: showContent)
                
                VStack(spacing: 8) {
                    Text("Welcome to CutClip!")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                    
                    Text("Your YouTube video clipping companion")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .opacity(showContent ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.4), value: showContent)
            }
            
            // Content
            VStack(spacing: 24) {
                Text("Let's get you set up! First, here's what you need to know:")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.6).delay(0.6), value: showContent)

                VStack(spacing: 16) {
                    DisclaimerPoint(
                        icon: "checkmark.shield.fill",
                        text: "You're responsible for following YouTube's Terms of Service",
                        delay: 0.8
                    )
                    
                    DisclaimerPoint(
                        icon: "person.fill.checkmark",
                        text: "Only download content you have permission to use",
                        delay: 1.0
                    )
                    
                    DisclaimerPoint(
                        icon: "heart.fill",
                        text: "Use this tool responsibly and respect creators' rights",
                        delay: 1.2
                    )
                }
            }
            .opacity(showContent ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(0.8), value: showContent)

            // Terms Agreement
            Text("By continuing, you agree to our [Terms and Conditions](https://cutclip.moinulmoin.com/terms) and [Privacy Policy](https://cutclip.moinulmoin.com/privacy)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(showContent ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(1.2), value: showContent)

            // Accept Button
            Button("I Understand and Accept") {
                accepted = true
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.gradient)
            )
            .buttonStyle(.plain)
            .opacity(showContent ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(1.4), value: showContent)
            }
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(width: 500, height: 450)
        .onAppear {
            showContent = true
        }
    }
}

struct DisclaimerPoint: View {
    let icon: String
    let text: String
    let delay: Double
    @State private var show = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.black.gradient)
                .frame(width: 20)
            
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .opacity(show ? 1.0 : 0.0)
        .offset(x: show ? 0 : -20)
        .animation(.easeInOut(duration: 0.5).delay(delay), value: show)
        .onAppear {
            show = true
        }
    }
}

#Preview {
    DisclaimerView()
}