//
//  LicenseStatus.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Represents the various states of license and trial status
enum LicenseStatus: Equatable {
    case unknown
    case unlicensed
    case freeTrial(remaining: Int)
    case trialExpired
    case licensed(key: String, expiresAt: Date?, userEmail: String?)

    var displayText: String {
        switch self {
        case .unknown:
            return "Checking license..."
        case .unlicensed:
            return "No license"
        case .freeTrial(let remaining):
            return "Free trial (\(remaining) uses left)"
        case .trialExpired:
            return "Trial expired"
        case .licensed(_, let expiresAt, _):
            if let expiry = expiresAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return "Licensed until \(formatter.string(from: expiry))"
            } else {
                return "Licensed"
            }
        }
    }

    var canUseApp: Bool {
        switch self {
        case .licensed:
            return true
        case .freeTrial(let remaining):
            return remaining > 0
        case .unknown, .unlicensed, .trialExpired:
            return false
        }
    }

    var requiresLicenseSetup: Bool {
        switch self {
        case .trialExpired, .unlicensed:
            return true
        case .freeTrial(let remaining):
            return remaining == 0
        case .licensed, .unknown:
            return false
        }
    }

    var debugDescription: String {
        switch self {
        case .unknown:
            return "unknown"
        case .unlicensed:
            return "unlicensed"
        case .freeTrial(let remaining):
            return "freeTrial(\(remaining))"
        case .trialExpired:
            return "trialExpired"
        case .licensed(let key, let expiresAt, let email):
            return "licensed(key: \(key.prefix(8))..., expires: \(expiresAt?.description ?? "never"), email: \(email ?? "none"))"
        }
    }
}