//
//  ClipperView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import SwiftUI

struct ClipperView: View {
    @State private var urlText = ""
    @State private var startTime = "00:00:00"
    @State private var endTime = "00:00:10"
    @State private var selectedRatio = "Original"
    @AppStorage("bangersClipped") private var bangersCount = 0

    var body: some View {
        VStack(spacing: 20) {
            // URL Input
            HStack {
                TextField("https://www.youtube.com/watch?v=...", text: $urlText)
                    .textFieldStyle(.roundedBorder)

                Button(action: download) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.largeTitle)
                }
            }

            // Time inputs
            HStack {
                VStack(alignment: .leading) {
                    Text("Start At").font(.caption)
                    TextField("00:00:00", text: $startTime)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("End At").font(.caption)
                    TextField("00:00:10", text: $endTime)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("Ratio").font(.caption)
                    Picker("", selection: $selectedRatio) {
                        Text("Original").tag("Original")
                        Text("16:9").tag("16:9")
                        Text("1:1").tag("1:1")
                    }
                }
            }

            // Status
            Text("🔥 \(bangersCount) bangers clipped")
                .foregroundColor(.orange)
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .frame(width: 600, height: 200)
    }
    
    private func download() {
        // TODO: Implement download functionality
        print("Download button pressed")
        print("URL: \(urlText)")
        print("Start: \(startTime), End: \(endTime)")
        print("Ratio: \(selectedRatio)")
    }
}

#Preview {
    ClipperView()
}