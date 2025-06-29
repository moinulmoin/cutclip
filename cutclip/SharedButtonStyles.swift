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
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.bodyBold)
            .foregroundColor(DesignSystem.Colors.textOnPrimary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button)
                    .fill(isEnabled ? DesignSystem.Colors.primary : DesignSystem.Colors.primary.opacity(0.5))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.body)
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.bodyBold)
            .foregroundColor(DesignSystem.Colors.textOnPrimary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button)
                    .fill(isEnabled ? DesignSystem.Colors.primary : DesignSystem.Colors.primary.opacity(0.5))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.body)
            .foregroundColor(DesignSystem.Colors.primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
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