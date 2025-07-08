//
//  LicenseStateManager.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Manages license state synchronization between different services
@MainActor
class LicenseStateManager {
    private let secureStorage: SecureStorage
    private let usageTracker: UsageTracker
    
    // Callbacks for state updates
    var onLicenseStatusChange: (@MainActor @Sendable (LicenseStatus) -> Void)?
    var onNeedsSetupChange: (@MainActor @Sendable (Bool) -> Void)?
    
    init(secureStorage: SecureStorage, usageTracker: UsageTracker) {
        self.secureStorage = secureStorage
        self.usageTracker = usageTracker
    }
    
    /// Synchronize license state between storage and usage tracker
    func syncLicenseState() async -> LicenseStatus {
        let currentStatus = usageTracker.getUsageStatus()
        
        // Only update license status if we don't have a valid stored license
        guard secureStorage.retrieveLicense() == nil else {
            // If we have a stored license, ensure status reflects this
            if let storedLicense = secureStorage.retrieveLicense() {
                let status = LicenseStatus.licensed(
                    key: storedLicense.key,
                    expiresAt: nil,
                    userEmail: nil
                )
                onLicenseStatusChange?(status)
                return status
            }
            return .unknown
        }
        
        // Sync license status with usage tracker state
        let licenseStatus: LicenseStatus
        switch currentStatus {
        case .licensed:
            // This shouldn't happen since we checked for stored license above
            // But handle it gracefully
            if let storedLicense = secureStorage.retrieveLicense() {
                licenseStatus = .licensed(key: storedLicense.key, expiresAt: nil, userEmail: nil)
            } else {
                licenseStatus = .unlicensed
            }
        case .freeTrial(let remaining):
            licenseStatus = .freeTrial(remaining: remaining)
        case .trialExpired:
            licenseStatus = .trialExpired
        }
        
        print("🔄 State synchronized: \(licenseStatus.debugDescription)")
        onLicenseStatusChange?(licenseStatus)
        return licenseStatus
    }
    
    /// Determine if license setup is required based on current state
    func determineLicenseSetupRequired(currentLicenseStatus: LicenseStatus) async -> Bool {
        // Ensure license status and usage status are synchronized
        let hasStoredLicense = secureStorage.hasValidLicense()
        let usageStatus = usageTracker.getUsageStatus()
        
        // If we have a stored license but status shows unlicensed, there's a mismatch
        if hasStoredLicense, case .licensed = currentLicenseStatus {
            return false
        }
        
        // If UsageTracker shows licensed but we don't have stored license, sync issue
        if !hasStoredLicense, case .licensed = usageStatus {
            // Clear the mismatch by invalidating cache
            await usageTracker.invalidateCache()
        }
        
        // Check final usage status after any synchronization
        let needsSetup: Bool
        switch usageStatus {
        case .licensed:
            needsSetup = false
        case .freeTrial(let remaining):
            needsSetup = remaining == 0  // Only require setup if no credits left
        case .trialExpired:
            needsSetup = true
        }
        
        onNeedsSetupChange?(needsSetup)
        return needsSetup
    }
    
    /// Update license status after validation
    func updateLicenseStatus(licenseKey: String, isValid: Bool) -> LicenseStatus {
        let status: LicenseStatus
        if isValid {
            status = .licensed(
                key: licenseKey,
                expiresAt: nil,  // No expiration from API
                userEmail: nil   // No user email from API
            )
        } else {
            status = .unlicensed
        }
        
        onLicenseStatusChange?(status)
        return status
    }
    
    /// Reset license status for testing
    func resetLicenseStatus() {
        onLicenseStatusChange?(.unknown)
        onNeedsSetupChange?(false)
    }
}