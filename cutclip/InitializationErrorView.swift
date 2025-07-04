//
//  InitializationErrorView.swift
//  cutclip
//
//  Created by Moinul Moin on 6/30/25.
//

import SwiftUI

struct InitializationErrorView: View {
    let error: AppError
    let onRetry: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: CleanDS.Spacing.lg) {
            // Error Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            // Error Title
            Text(error.errorTitle)
                .font(CleanDS.Typography.title)
                .foregroundColor(CleanDS.Colors.textPrimary)
            
            // Error Message
            VStack(spacing: CleanDS.Spacing.sm) {
                Text(error.errorDescription ?? "An error occurred")
                    .font(CleanDS.Typography.body)
                    .foregroundColor(CleanDS.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(CleanDS.Typography.caption)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, CleanDS.Spacing.md)
            
            // Buttons
            HStack(spacing: CleanDS.Spacing.md) {
                if error.isRetryable {
                    CleanActionButton("Retry", style: .secondary, action: onRetry)
                }
                
                CleanActionButton("Quit", style: .primary, action: onQuit)
                    .tint(.red)
            }
        }
        .padding(CleanDS.Spacing.containerNormal)
        .frame(minWidth: 400, idealWidth: 420, maxWidth: 500)
        .background(.regularMaterial)
        .cornerRadius(CleanDS.Radius.medium)
    }
}