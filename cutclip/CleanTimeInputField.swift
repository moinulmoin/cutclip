//
//  CleanTimeInputField.swift
//  cutclip
//
//  Created by Assistant on 7/8/24.
//

import SwiftUI

struct CleanTimeInputField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let isDisabled: Bool
    
    @State private var rawInput: String = ""
    @FocusState private var isFocused: Bool
    
    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "00:00:00",
        isDisabled: Bool = false
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.isDisabled = isDisabled
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: CleanDS.Spacing.xs) {
            CleanLabel(text: label)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(CleanDS.Typography.body)
                .foregroundColor(CleanDS.Colors.textPrimary)
                .disabled(isDisabled)
                .cleanInput()
                .onChange(of: text) { oldValue, newValue in
                    // Only process if the new value is different
                    if newValue != oldValue {
                        let filtered = filterAndFormatTime(newValue, previousValue: oldValue)
                        if filtered != newValue {
                            text = filtered
                        }
                    }
                }
                .onAppear {
                    // Initialize raw input from existing formatted text
                    rawInput = text.replacingOccurrences(of: ":", with: "")
                }
        }
    }
    
    private func filterAndFormatTime(_ input: String, previousValue: String) -> String {
        // Remove all non-numeric characters
        let numbersOnly = input.filter { $0.isNumber }
        
        // If backspace was pressed (new value is shorter)
        if input.count < previousValue.count {
            // Handle backspace by removing from raw numbers
            let rawPrevious = previousValue.replacingOccurrences(of: ":", with: "")
            if rawPrevious.count > numbersOnly.count {
                return formatTimeString(numbersOnly)
            }
        }
        
        // Limit to 6 digits (HHMMSS)
        let limited = String(numbersOnly.prefix(6))
        
        // Format the string with colons
        return formatTimeString(limited)
    }
    
    private func formatTimeString(_ numbers: String) -> String {
        var result = ""
        
        for (index, char) in numbers.enumerated() {
            if index == 2 || index == 4 {
                result += ":"
            }
            result += String(char)
        }
        
        // Pad with zeros if needed to maintain format
        switch result.count {
        case 0: return ""
        case 1: return result // Single digit
        case 2: return result // Two digits
        case 3: return result // Two digits + colon
        case 4: return result // HH:M
        case 5: return result // HH:MM
        case 6: return result // HH:MM:
        case 7: return result // HH:MM:S
        case 8: return result // HH:MM:SS
        default: return result
        }
    }
}

// Extension to check if character is a number
extension Character {
    var isNumber: Bool {
        return self >= "0" && self <= "9"
    }
}