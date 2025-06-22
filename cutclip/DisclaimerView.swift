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
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange.gradient)
                    .scaleEffect(showContent ? 1.0 : 0.5)
                    .animation(.bouncy(duration: 0.8).delay(0.2), value: showContent)
                
                Text("Important Notice")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.6).delay(0.4), value: showContent)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 20) {
                Text("This app requires you to provide your own yt-dlp and FFmpeg binaries.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.6).delay(0.6), value: showContent)

                VStack(alignment: .leading, spacing: 12) {
                    Text("By using this app, you acknowledge that:")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        DisclaimerPoint(
                            icon: "checkmark.shield.fill",
                            text: "You are responsible for compliance with YouTube's Terms of Service",
                            delay: 0.8
                        )
                        
                        DisclaimerPoint(
                            icon: "person.fill.checkmark",
                            text: "You will only download content you have permission to download",
                            delay: 1.0
                        )
                        
                        DisclaimerPoint(
                            icon: "hand.raised.fill",
                            text: "The developers are not responsible for how you use this tool",
                            delay: 1.2
                        )
                    }
                }
            }
            .opacity(showContent ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(0.8), value: showContent)

            // Accept Button
            Button("I Understand and Accept") {
                accepted = true
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.purple.gradient)
            )
            .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
            .scaleEffect(showContent ? 1.0 : 0.8)
            .opacity(showContent ? 1.0 : 0.0)
            .animation(.bouncy(duration: 0.8).delay(1.4), value: showContent)
            .buttonStyle(.plain)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 30, x: 0, y: 15)
        )
        .frame(width: 580)
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
                .foregroundStyle(.purple.gradient)
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