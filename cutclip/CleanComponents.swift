//
//  CleanComponents.swift
//  cutclip
//
//  Created by Moinul Moin on 6/28/25.
//

import SwiftUI

// MARK: - Clean Input Field
struct CleanInputField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let isDisabled: Bool
    let onTextChange: (() -> Void)?
    let errorMessage: String?
    
    @FocusState private var isFocused: Bool
    
    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        isDisabled: Bool = false,
        errorMessage: String? = nil,
        onTextChange: (() -> Void)? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.isDisabled = isDisabled
        self.errorMessage = errorMessage
        self.onTextChange = onTextChange
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
            CleanLabel(text: label)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(CleanDS.Typography.body)
                .foregroundColor(CleanDS.Colors.textPrimary)
                .disabled(isDisabled)
                .cleanInput(hasError: errorMessage != nil)
                .onChange(of: text) { _, _ in
                    onTextChange?()
                }
            
            if let error = errorMessage {
                Text(error)
                    .font(CleanDS.Typography.caption)
                    .foregroundColor(CleanDS.Colors.error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Clean Input with Trailing Action
struct CleanInputWithAction<TrailingContent: View>: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let isDisabled: Bool
    let onTextChange: (() -> Void)?
    let errorMessage: String?
    let trailingContent: () -> TrailingContent
    
    @FocusState private var isFocused: Bool
    
    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        isDisabled: Bool = false,
        errorMessage: String? = nil,
        onTextChange: (() -> Void)? = nil,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.isDisabled = isDisabled
        self.errorMessage = errorMessage
        self.onTextChange = onTextChange
        self.trailingContent = trailingContent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
            CleanLabel(text: label)
            
            HStack(spacing: CleanDS.Spacing.sm) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(CleanDS.Typography.body)
                    .foregroundColor(CleanDS.Colors.textPrimary)
                    .disabled(isDisabled)
                    .cleanInput(hasError: errorMessage != nil)
                    .onChange(of: text) { _, _ in
                        onTextChange?()
                    }
                
                trailingContent()
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(CleanDS.Typography.caption)
                    .foregroundColor(CleanDS.Colors.error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Clean Picker Field
struct CleanPickerField<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [T]
    let displayText: (T) -> String
    let isDisabled: Bool
    
    init(
        label: String,
        selection: Binding<T>,
        options: [T],
        displayText: @escaping (T) -> String,
        isDisabled: Bool = false
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.displayText = displayText
        self.isDisabled = isDisabled
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
            CleanLabel(text: label)
            
            // Use a ZStack to overlay picker on TextField-styled container
            ZStack {
                // TextField-styled background
                HStack {
                    Text(displayText(selection))
                        .font(CleanDS.Typography.body)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(CleanDS.Colors.textSecondary)
                }
                .cleanInput() // Use the exact same modifier as TextField!
                
                // Invisible picker overlay
                Picker("", selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(displayText(option)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .opacity(0.05) // Almost invisible but still interactive
                .allowsHitTesting(true)
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.6 : 1.0)
        }
    }
}

// Convenience initializers for common types
extension CleanPickerField where T == String {
    init(
        label: String,
        selection: Binding<String>,
        options: [String],
        isDisabled: Bool = false
    ) {
        self.init(
            label: label,
            selection: selection,
            options: options,
            displayText: { $0 },
            isDisabled: isDisabled
        )
    }
}

extension CleanPickerField where T == ClipJob.AspectRatio {
    init(
        label: String,
        selection: Binding<ClipJob.AspectRatio>,
        options: [ClipJob.AspectRatio],
        isDisabled: Bool = false
    ) {
        self.init(
            label: label,
            selection: selection,
            options: options,
            displayText: { $0.rawValue },
            isDisabled: isDisabled
        )
    }
}

// MARK: - Clean Video Preview
struct CleanVideoPreview: View {
    let videoInfo: VideoInfo
    let onChangeVideo: (() -> Void)?
    let isChangeDisabled: Bool
    
    init(videoInfo: VideoInfo, onChangeVideo: (() -> Void)? = nil, isChangeDisabled: Bool = false) {
        self.videoInfo = videoInfo
        self.onChangeVideo = onChangeVideo
        self.isChangeDisabled = isChangeDisabled
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: CleanDS.Spacing.md) {
                // Clean thumbnail
                AsyncImage(url: URL(string: videoInfo.thumbnailURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(CleanDS.Colors.backgroundTertiary)
                        .overlay(
                            Image(systemName: "play.rectangle")
                                .font(CleanDS.Typography.title)
                                .foregroundColor(CleanDS.Colors.textTertiary)
                        )
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: CleanDS.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: CleanDS.Radius.small)
                        .stroke(CleanDS.Colors.borderLight, lineWidth: 1)
                )
                
                // Clean video details
                VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                    Text(videoInfo.title)
                        .font(CleanDS.Typography.bodyMedium)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: CleanDS.Spacing.md) {
                        // Duration
                        Label(videoInfo.durationFormatted, systemImage: "clock")
                            .font(CleanDS.Typography.caption)
                            .foregroundColor(CleanDS.Colors.textSecondary)
                        
                        // Channel
                        if let channelName = videoInfo.channelName {
                            Label(channelName, systemImage: "person.circle")
                                .font(CleanDS.Typography.caption)
                                .foregroundColor(CleanDS.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // Quality info - Show only highest available
                    if let highestQuality = videoInfo.highestAvailableQuality {
                        Text("Up to \(highestQuality)")
                            .font(CleanDS.Typography.caption)
                            .foregroundColor(CleanDS.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(CleanDS.Spacing.md)
            
            // Change button at bottom of card
            if let onChangeVideo = onChangeVideo {
                Divider()
                    .background(CleanDS.Colors.borderLight)
                
                CleanActionButton("Change", style: .ghost, isDisabled: isChangeDisabled) {
                    onChangeVideo()
                }
                .padding(.horizontal, CleanDS.Spacing.sm)
                .padding(.vertical, CleanDS.Spacing.xs)
            }
        }
        .background(CleanDS.Colors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: CleanDS.Radius.medium)
                .stroke(CleanDS.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(CleanDS.Radius.medium)
    }
}

// MARK: - Clean Progress Section
struct CleanProgressSection: View {
    let title: String
    let message: String
    let progress: Double
    let onCancel: (() -> Void)?
    
    init(
        title: String,
        message: String,
        progress: Double,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.progress = progress
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: CleanDS.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
                    Text(title)
                        .font(CleanDS.Typography.bodyMedium)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                    
                    Text(message)
                        .font(CleanDS.Typography.caption)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                }
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(CleanDS.Typography.captionMedium)
                    .foregroundColor(CleanDS.Colors.accent)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: CleanDS.Colors.accent))
                .frame(height: 4)
            
            // Prominent Cancel Button
            if let onCancel = onCancel {
                CleanActionButton(
                    "Cancel",
                    icon: "xmark.circle.fill",
                    style: .destructive,
                    action: onCancel
                )
            }
        }
        .cleanSection()
    }
}

// MARK: - Clean Action Button
struct CleanActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    let isDisabled: Bool
    let style: ButtonStyleType
    
    enum ButtonStyleType {
        case primary, secondary, ghost, destructive
    }
    
    @State private var isHovered = false
    
    init(
        _ title: String,
        icon: String = "",
        style: ButtonStyleType = .primary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: CleanDS.Spacing.xs) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(CleanDS.Typography.bodyMedium)
                }
                Text(title)
                    .font(CleanDS.Typography.bodyMedium)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isDisabled)
        .scaleEffect(isHovered && !isDisabled ? 1.01 : 1.0)
        .animation(CleanDS.Animation.quick, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .if(style == .primary) { view in
            view.buttonStyle(CleanPrimaryButtonStyle())
        }
        .if(style == .secondary) { view in
            view.buttonStyle(CleanSecondaryButtonStyle())
        }
        .if(style == .ghost) { view in
            view.buttonStyle(CleanGhostButtonStyle())
        }
        .if(style == .destructive) { view in
            view.buttonStyle(CleanDestructiveButtonStyle())
        }
    }
}

// MARK: - Clean Success Section
struct CleanSuccessSection: View {
    let onOpenVideo: () -> Void
    let onShowInFinder: () -> Void
    let onNewClip: () -> Void
    
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: CleanDS.Spacing.lg) {
            // Clean success indicator
            VStack(spacing: CleanDS.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(CleanDS.Colors.success)
                    .scaleEffect(showSuccess ? 1.0 : 0.5)
                    .animation(CleanDS.Animation.smooth.delay(0.05), value: showSuccess)
                
                VStack(spacing: CleanDS.Spacing.xs) {
                    Text("Clip Ready")
                        .font(CleanDS.Typography.title)
                        .foregroundColor(CleanDS.Colors.textPrimary)
                    
                    Text("Your video clip has been created")
                        .font(CleanDS.Typography.caption)
                        .foregroundColor(CleanDS.Colors.textSecondary)
                }
                .opacity(showSuccess ? 1.0 : 0.0)
                .animation(CleanDS.Animation.standard.delay(0.1), value: showSuccess)
            }
            
            // Clean action buttons
            VStack(spacing: CleanDS.Spacing.sm) {
                HStack(spacing: CleanDS.Spacing.sm) {
                    CleanActionButton("Open Video", style: .primary) {
                        onOpenVideo()
                    }
                    
                    CleanActionButton("Show in Finder", style: .secondary) {
                        onShowInFinder()
                    }
                }
                
                CleanActionButton("New Clip", style: .ghost) {
                    onNewClip()
                }
            }
            .opacity(showSuccess ? 1.0 : 0.0)
            .animation(CleanDS.Animation.standard.delay(0.15), value: showSuccess)
        }
        .cleanSection()
        .onAppear {
            showSuccess = true
        }
    }
}

// MARK: - Clean Status Indicator
struct CleanStatusIndicator: View {
    let licenseStatus: LicenseStatus
    let onUpgrade: () -> Void
    
    var body: some View {
        HStack(spacing: CleanDS.Spacing.xs) {
            switch licenseStatus {
            case .licensed:
                CleanStatusBadge(text: "Pro", color: CleanDS.Colors.success)
                
            case .freeTrial(let remaining):
                CleanStatusBadge(
                    text: "\(remaining) left",
                    color: remaining <= 1 ? CleanDS.Colors.warning : CleanDS.Colors.info
                )
                
            case .trialExpired, .unlicensed:
                Button("Get Pro") {
                    onUpgrade()
                }
                .cleanGhostButton()
                
            case .unknown:
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }
}

// MARK: - View Utility Extensions
extension View {
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}