//
//  ModernComponents.swift
//  cutclip
//
//  Created by Moinul Moin on 6/28/25.
//

import SwiftUI

// MARK: - Modern Input Field
struct ModernInputField<Trailing: View>: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let isDisabled: Bool
    let onTextChange: (() -> Void)?
    let trailing: (() -> Trailing)?
    
    @FocusState private var isFocused: Bool
    
    init(
        title: String,
        text: Binding<String>,
        placeholder: String,
        isDisabled: Bool = false,
        onTextChange: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.isDisabled = isDisabled
        self.onTextChange = onTextChange
        self.trailing = trailing
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.bodyBold)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .disabled(isDisabled)
                    .focused($isFocused)
                    .padding(DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.input)
                            .fill(DesignSystem.Colors.backgroundSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.input)
                                    .stroke(
                                        isFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
                                        lineWidth: isFocused ? 2 : 1
                                    )
                            )
                    )
                    .onChange(of: text) { _, _ in
                        onTextChange?()
                    }
                
                trailing?()
            }
        }
    }
}

// Convenience initializer for simple input fields
extension ModernInputField where Trailing == EmptyView {
    init(
        title: String,
        text: Binding<String>,
        placeholder: String,
        isDisabled: Bool = false,
        onTextChange: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            text: text,
            placeholder: placeholder,
            isDisabled: isDisabled,
            onTextChange: onTextChange,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Modern Picker Field (String)
struct ModernStringPickerField: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    let isDisabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.bodyBold)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .disabled(isDisabled)
            .padding(DesignSystem.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.input)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.input)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Modern Picker Field (AspectRatio)
struct ModernAspectRatioPickerField: View {
    let title: String
    @Binding var selection: ClipJob.AspectRatio
    let options: [ClipJob.AspectRatio]
    let isDisabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.bodyBold)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .disabled(isDisabled)
            .padding(DesignSystem.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.input)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.input)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Modern Video Preview Card
struct ModernVideoPreviewCard: View {
    let videoInfo: VideoInfo
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Enhanced Thumbnail
            AsyncImage(url: URL(string: videoInfo.thumbnailURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(DesignSystem.Colors.backgroundTertiary)
                    .overlay(
                        VStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "play.rectangle")
                                .font(DesignSystem.Typography.title2)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text("Loading...")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    )
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
            )
            
            // Enhanced Video Details
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(videoInfo.title)
                    .font(DesignSystem.Typography.bodyBold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Duration
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Text(videoInfo.durationFormatted)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    // Channel
                    if let channelName = videoInfo.channelName {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "person.circle")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text(channelName)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Quality Options
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "video")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("\(videoInfo.qualityOptions.joined(separator: ", "))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            Spacer()
        }
        .cardStyle()
        .animation(DesignSystem.Animation.standard, value: videoInfo.title)
    }
}

// MARK: - Modern Action Button
struct ModernActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    let isDisabled: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.bodyBold)
                Text(title)
                    .font(DesignSystem.Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
        }
        .primaryButtonStyle()
        .disabled(isDisabled)
        .scaleEffect(isHovered && !isDisabled ? 1.02 : 1.0)
        .animation(DesignSystem.Animation.quick, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Modern Completion Card
struct ModernCompletionCard: View {
    let onOpenVideo: () -> Void
    let onShowInFinder: () -> Void
    let onNewClip: () -> Void
    
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Success Header
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(DesignSystem.Colors.success)
                    .scaleEffect(showSuccess ? 1.0 : 0.5)
                    .animation(DesignSystem.Animation.spring.delay(0.1), value: showSuccess)
                
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Clip Ready!")
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("Your video clip has been created successfully")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showSuccess ? 1.0 : 0.0)
                .animation(DesignSystem.Animation.standard.delay(0.3), value: showSuccess)
            }
            
            // Action Buttons
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button("Open Video") {
                        onOpenVideo()
                    }
                    .primaryButtonStyle()
                    
                    Button("Show in Finder") {
                        onShowInFinder()
                    }
                    .secondaryButtonStyle()
                }
                
                Button("Create New Clip") {
                    onNewClip()
                }
                .textButtonStyle()
            }
            .opacity(showSuccess ? 1.0 : 0.0)
            .animation(DesignSystem.Animation.standard.delay(0.5), value: showSuccess)
        }
        .cardStyle()
        .onAppear {
            showSuccess = true
        }
    }
}