//
//  DisclaimerView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct DisclaimerView: View {
    @AppStorage("disclaimerAccepted") private var accepted = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Important Notice")
                .font(.title)

            Text("""
            This app requires you to provide your own yt-dlp and FFmpeg binaries.

            By using this app, you acknowledge that:
            • You are responsible for compliance with YouTube's Terms of Service
            • You will only download content you have permission to download
            • The developers are not responsible for how you use this tool
            """)
            .multilineTextAlignment(.leading)

            Button("I Understand and Accept") {
                accepted = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 500)
    }
}

#Preview {
    DisclaimerView()
}