//
//  DesignSystem.swift
//  cutclip
//
//  Created by Moinul Moin on 6/28/25.
//

import SwiftUI

// MARK: - Design System
struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Primary - YouTube Brand
        static let primary = Color(red: 255/255, green: 0/255, blue: 0/255) // YouTube Red
        static let primaryDark = Color(red: 204/255, green: 0/255, blue: 0/255)
        static let primaryLight = Color(red: 255/255, green: 68/255, blue: 68/255)
        
        // Backgrounds
        static let backgroundPrimary = Color(NSColor.windowBackgroundColor)
        static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
        static let backgroundTertiary = Color(NSColor.underPageBackgroundColor)
        
        // Text
        static let textPrimary = Color(NSColor.labelColor)
        static let textSecondary = Color(NSColor.secondaryLabelColor)
        static let textTertiary = Color(NSColor.tertiaryLabelColor)
        static let textOnPrimary = Color.white
        
        // UI Elements
        static let divider = Color(NSColor.separatorColor)
        static let border = Color(NSColor.separatorColor).opacity(0.5)
        
        // Status Colors
        static let success = Color(NSColor.systemGreen)
        static let warning = Color(NSColor.systemOrange)
        static let error = Color(NSColor.systemRed)
        static let info = Color(NSColor.systemBlue)
    }
    
    // MARK: - Typography
    struct Typography {
        // Headers
        static let largeTitle = Font.system(size: 28, weight: .semibold, design: .default)
        static let title1 = Font.system(size: 24, weight: .semibold, design: .default)
        static let title2 = Font.system(size: 20, weight: .medium, design: .default)
        static let title3 = Font.system(size: 18, weight: .medium, design: .default)
        
        // Body
        static let body = Font.system(size: 13, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 13, weight: .semibold, design: .default)
        static let bodyLarge = Font.system(size: 14, weight: .regular, design: .default)
        
        // Small
        static let caption = Font.system(size: 11, weight: .regular, design: .default)
        static let captionBold = Font.system(size: 11, weight: .medium, design: .default)
        static let footnote = Font.system(size: 12, weight: .regular, design: .default)
        
        // Monospace
        static let code = Font.system(size: 12, weight: .regular, design: .monospaced)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        
        // Specific Use Cases
        static let contentPadding: CGFloat = 24
        static let modalPadding: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let buttonPadding: CGFloat = 12
    }
    
    // MARK: - Layout
    struct Layout {
        static let defaultWindowWidth: CGFloat = 700
        static let defaultWindowHeight: CGFloat = 500
        static let minWindowWidth: CGFloat = 600
        static let minWindowHeight: CGFloat = 400
        
        static let maxContentWidth: CGFloat = 600
        static let compactContentWidth: CGFloat = 400
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        
        // Specific Use Cases
        static let button: CGFloat = 8
        static let card: CGFloat = 12
        static let modal: CGFloat = 16
        static let input: CGFloat = 6
    }
    
    // MARK: - Shadows
    struct Shadows {
        static func subtle() -> some View {
            return EmptyView().shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        
        static func card() -> some View {
            return EmptyView().shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        
        static func elevated() -> some View {
            return EmptyView().shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
    }
    
    // MARK: - Animation
    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
    }
}

// MARK: - Reusable View Modifiers

// Card Container Modifier
struct CardStyle: ViewModifier {
    var padding: CGFloat = DesignSystem.Spacing.cardPadding
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignSystem.Colors.backgroundSecondary)
            .cornerRadius(DesignSystem.CornerRadius.card)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

// Window Background Modifier
struct WindowBackgroundStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                DesignSystem.Colors.backgroundPrimary
                    .ignoresSafeArea()
            )
    }
}

// Content Container Modifier
struct ContentContainerStyle: ViewModifier {
    var maxWidth: CGFloat = DesignSystem.Layout.maxContentWidth
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Extensions
extension View {
    func primaryButtonStyle() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
    }
    
    func secondaryButtonStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
    
    func textButtonStyle() -> some View {
        self.buttonStyle(LinkButtonStyle())
    }
    
    func cardStyle(padding: CGFloat = DesignSystem.Spacing.cardPadding) -> some View {
        self.modifier(CardStyle(padding: padding))
    }
    
    func windowBackgroundStyle() -> some View {
        self.modifier(WindowBackgroundStyle())
    }
    
    func contentContainerStyle(maxWidth: CGFloat = DesignSystem.Layout.maxContentWidth) -> some View {
        self.modifier(ContentContainerStyle(maxWidth: maxWidth))
    }
}

// MARK: - Custom Components

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(DesignSystem.Typography.title3)
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InfoCard: View {
    let title: String
    let message: String
    let type: InfoType
    
    enum InfoType {
        case info, success, warning, error
        
        var color: Color {
            switch self {
            case .info: return DesignSystem.Colors.info
            case .success: return DesignSystem.Colors.success
            case .warning: return DesignSystem.Colors.warning
            case .error: return DesignSystem.Colors.error
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(DesignSystem.Typography.bodyBold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .cardStyle()
    }
}