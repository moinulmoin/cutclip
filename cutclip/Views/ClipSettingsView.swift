//
//  ClipSettingsView.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import SwiftUI

struct ClipSettingsView: View {
    @Binding var startTime: String
    @Binding var endTime: String
    @Binding var selectedQuality: String
    @Binding var selectedAspectRatio: ClipJob.AspectRatio
    
    let qualityOptions: [String]
    let aspectRatioOptions: [ClipJob.AspectRatio]
    let isDisabled: Bool
    
    var body: some View {
        VStack(spacing: CleanDS.Spacing.md) {
            CleanSectionHeader(title: "Clip Settings")
            
            // Time inputs
            HStack(spacing: CleanDS.Spacing.md) {
                CleanInputField(
                    label: "Start Time",
                    text: $startTime,
                    placeholder: "00:00:00",
                    isDisabled: isDisabled
                )
                
                CleanInputField(
                    label: "End Time",
                    text: $endTime,
                    placeholder: "00:00:10",
                    isDisabled: isDisabled
                )
            }
            
            // Quality and aspect ratio
            HStack(spacing: CleanDS.Spacing.md) {
                CleanPickerField(
                    label: "Quality",
                    selection: $selectedQuality,
                    options: qualityOptions,
                    isDisabled: isDisabled
                )
                
                CleanPickerField(
                    label: "Aspect Ratio",
                    selection: $selectedAspectRatio,
                    options: aspectRatioOptions,
                    isDisabled: isDisabled
                )
            }
        }
        .cleanSection()
    }
}