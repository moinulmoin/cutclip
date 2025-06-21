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
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    
    var body: some View {
        Group {
            if !disclaimerAccepted {
                DisclaimerView()
            } else if !binaryManager.isConfigured {
                AutoSetupView(binaryManager: binaryManager)
            } else {
                ClipperView()
                    .environmentObject(binaryManager)
                    .environmentObject(errorHandler)
            }
        }
        .errorAlert(errorHandler)
    }
}

#Preview {
    ContentView()
}
