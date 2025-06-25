//
//  SharedButtonStyles.swift
//  cutclip
//
//  Created by Moinul Moin on 6/24/25.
//

import SwiftUI

/// Centralized button styles for consistent UI across the app
extension ButtonStyle {
    
    /// Primary action button (used for main actions)
    static var primary: some ButtonStyle {
        PrimaryButtonStyle()
    }
    
    /// Secondary action button (used for secondary actions)
    static var secondary: some ButtonStyle {
        SecondaryButtonStyle()
    }
    
    /// Accent button for special actions
    static var accent: some ButtonStyle {
        AccentButtonStyle()
    }
    
    /// Link-style button for less important actions
    static var link: some ButtonStyle {
        LinkButtonStyle()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.gradient)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue.gradient)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(.blue)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Shared animation utilities
extension Animation {
    static var buttonPress: Animation {
        .easeInOut(duration: 0.1)
    }
    
    static var fadeIn: Animation {
        .easeInOut(duration: 0.6)
    }
    
    static var bounceIn: Animation {
        .bouncy(duration: 0.8)
    }
}