//
//  CleanDesignSystem.swift
//  cutclip
//
//  Created by Moinul Moin on 6/28/25.
//

import SwiftUI

// MARK: - Clean Design System
/// Minimal, clean design system focusing on content and native macOS feel
struct CleanDS {
    
    // MARK: - Colors
    struct Colors {
        // Background Layers (Clean, minimal)
        static let backgroundPrimary = Color(NSColor.windowBackgroundColor) // Clean white
        static let backgroundSecondary = Color(red: 245/255, green: 245/255, blue: 247/255) // #F5F5F7
        static let backgroundTertiary = Color(red: 238/255, green: 238/255, blue: 238/255) // #EEEEEE
        
        // Text Colors (High contrast, readable)
        static let textPrimary = Color(red: 29/255, green: 29/255, blue: 31/255) // #1D1D1F
        static let textSecondary = Color(red: 110/255, green: 110/255, blue: 115/255) // #6E6E73
        static let textTertiary = Color(red: 174/255, green: 174/255, blue: 178/255) // #AEAEB2
        
        // Single Accent Color (YouTube Red)
        static let accent = Color(red: 255/255, green: 0/255, blue: 0/255) // #FF0000
        static let accentSecondary = Color(red: 255/255, green: 68/255, blue: 68/255) // Lighter variant
        
        // Semantic Colors
        static let success = Color(red: 52/255, green: 199/255, blue: 89/255) // #34C759
        static let warning = Color(red: 255/255, green: 149/255, blue: 0/255) // #FF9500
        static let error = Color(red: 255/255, green: 59/255, blue: 48/255) // #FF3B30
        static let info = Color(red: 0/255, green: 122/255, blue: 255/255) // #007AFF
        
        // Border Colors (Very subtle)
        static let border = Color.black.opacity(0.1) // rgba(0,0,0,0.1)
        static let borderLight = Color.black.opacity(0.05) // rgba(0,0,0,0.05)
        static let borderMedium = Color.black.opacity(0.2) // rgba(0,0,0,0.2)
    }
    
    // MARK: - Typography
    struct Typography {
        // Headline (Page titles, section headers)
        static let headline = Font.system(size: 22, weight: .semibold, design: .default)
        
        // Title (Card titles, item names)
        static let title = Font.system(size: 17, weight: .medium, design: .default)
        static let titleLarge = Font.system(size: 18, weight: .medium, design: .default)
        
        // Body (Main content, descriptions)
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let bodyLarge = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 13, weight: .medium, design: .default)
        
        // Caption (Metadata, timestamps, secondary info)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 12, weight: .medium, design: .default)
        
        // Label (Form labels, categories)
        static let label = Font.system(size: 11, weight: .medium, design: .default)
        static let labelLarge = Font.system(size: 12, weight: .medium, design: .default)
    }
    
    // MARK: - Spacing (8px base system)
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
        
        // Container Padding
        static let containerTight: CGFloat = 16
        static let containerNormal: CGFloat = 24
        static let containerLoose: CGFloat = 40
        
        // Component Spacing
        static let withinComponent: CGFloat = 8
        static let betweenComponents: CGFloat = 20
        static let sectionSpacing: CGFloat = 32
    }
    
    // MARK: - Border Radius
    struct Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let window: CGFloat = 12
    }
    
    // MARK: - Shadows (Minimal, subtle)
    struct Shadow {
        static let subtle = (
            color: Color.black.opacity(0.1),
            radius: CGFloat(3),
            x: CGFloat(0),
            y: CGFloat(1)
        )
        
        static let medium = (
            color: Color.black.opacity(0.15),
            radius: CGFloat(12),
            x: CGFloat(0),
            y: CGFloat(4)
        )
        
        static let large = (
            color: Color.black.opacity(0.2),
            radius: CGFloat(24),
            x: CGFloat(0),
            y: CGFloat(8)
        )
    }
    
    // MARK: - Animation
    struct Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeOut(duration: 0.3)
        static let smooth = SwiftUI.Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)
    }
}

// MARK: - Clean Component Modifiers

/// Minimal section background - very subtle
struct CleanSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(CleanDS.Spacing.betweenComponents)
            .background(CleanDS.Colors.backgroundSecondary)
            .cornerRadius(CleanDS.Radius.medium)
    }
}

/// Clean input field styling
struct CleanInputStyle: ViewModifier {
    @FocusState private var isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .padding(.horizontal, CleanDS.Spacing.sm + 2)
            .padding(.vertical, CleanDS.Spacing.sm)
            .background(CleanDS.Colors.backgroundPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: CleanDS.Radius.small)
                    .stroke(
                        isFocused ? CleanDS.Colors.accent : CleanDS.Colors.border,
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .cornerRadius(CleanDS.Radius.small)
    }
}

/// Clean button styles - minimal, native
struct CleanPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CleanDS.Typography.bodyMedium)
            .foregroundColor(.white)
            .padding(.horizontal, CleanDS.Spacing.md)
            .padding(.vertical, CleanDS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CleanDS.Radius.small)
                    .fill(isEnabled ? CleanDS.Colors.accent : CleanDS.Colors.textTertiary)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(CleanDS.Animation.quick, value: configuration.isPressed)
    }
}

struct CleanSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CleanDS.Typography.body)
            .foregroundColor(CleanDS.Colors.textPrimary)
            .padding(.horizontal, CleanDS.Spacing.md)
            .padding(.vertical, CleanDS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CleanDS.Radius.small)
                    .fill(CleanDS.Colors.backgroundPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: CleanDS.Radius.small)
                            .stroke(CleanDS.Colors.border, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(CleanDS.Animation.quick, value: configuration.isPressed)
    }
}

struct CleanGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CleanDS.Typography.body)
            .foregroundColor(CleanDS.Colors.accent)
            .padding(.horizontal, CleanDS.Spacing.sm)
            .padding(.vertical, CleanDS.Spacing.xs)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(CleanDS.Animation.quick, value: configuration.isPressed)
    }
}

/// Clean window background - no heavy materials
struct CleanWindowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CleanDS.Colors.backgroundPrimary)
    }
}

/// Clean content container - proper max width and centering
struct CleanContentStyle: ViewModifier {
    let maxWidth: CGFloat
    
    init(maxWidth: CGFloat = 600) {
        self.maxWidth = maxWidth
    }
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - View Extensions
extension View {
    func cleanSection() -> some View {
        self.modifier(CleanSectionStyle())
    }
    
    func cleanInput() -> some View {
        self.modifier(CleanInputStyle())
    }
    
    func cleanPrimaryButton() -> some View {
        self.buttonStyle(CleanPrimaryButtonStyle())
    }
    
    func cleanSecondaryButton() -> some View {
        self.buttonStyle(CleanSecondaryButtonStyle())
    }
    
    func cleanGhostButton() -> some View {
        self.buttonStyle(CleanGhostButtonStyle())
    }
    
    func cleanWindow() -> some View {
        self.modifier(CleanWindowStyle())
    }
    
    func cleanContent(maxWidth: CGFloat = 600) -> some View {
        self.modifier(CleanContentStyle(maxWidth: maxWidth))
    }
    
    func cleanShadow(_ style: String = "subtle") -> some View {
        switch style {
        case "medium":
            return self.shadow(
                color: CleanDS.Shadow.medium.color,
                radius: CleanDS.Shadow.medium.radius,
                x: CleanDS.Shadow.medium.x,
                y: CleanDS.Shadow.medium.y
            )
        case "large":
            return self.shadow(
                color: CleanDS.Shadow.large.color,
                radius: CleanDS.Shadow.large.radius,
                x: CleanDS.Shadow.large.x,
                y: CleanDS.Shadow.large.y
            )
        default:
            return self.shadow(
                color: CleanDS.Shadow.subtle.color,
                radius: CleanDS.Shadow.subtle.radius,
                x: CleanDS.Shadow.subtle.x,
                y: CleanDS.Shadow.subtle.y
            )
        }
    }
}

// MARK: - Clean Components

/// Clean section header - minimal but clear
struct CleanSectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(CleanDS.Typography.title)
                .foregroundColor(CleanDS.Colors.textPrimary)
            Spacer()
        }
        .padding(.bottom, CleanDS.Spacing.xs)
    }
}

/// Clean form label - positioned above input
struct CleanLabel: View {
    let text: String
    
    var body: some View {
        HStack {
            Text(text)
                .font(CleanDS.Typography.labelLarge)
                .foregroundColor(CleanDS.Colors.textSecondary)
            Spacer()
        }
    }
}

/// Clean status badge - minimal, integrated
struct CleanStatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(CleanDS.Typography.captionMedium)
            .foregroundColor(color)
            .padding(.horizontal, CleanDS.Spacing.sm)
            .padding(.vertical, CleanDS.Spacing.xs)
            .background(color.opacity(0.1))
            .cornerRadius(CleanDS.Radius.small)
    }
}