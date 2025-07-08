//
//  LicenseAnalyticsService.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Handles analytics, debugging, and testing utilities for license system
@MainActor
class LicenseAnalyticsService {
    private let deviceIdentifier: DeviceIdentifier
    private let secureStorage: SecureStorage
    private let usageTracker: UsageTracker
    
    init(deviceIdentifier: DeviceIdentifier, secureStorage: SecureStorage, usageTracker: UsageTracker) {
        self.deviceIdentifier = deviceIdentifier
        self.secureStorage = secureStorage
        self.usageTracker = usageTracker
    }
    
    /// Get comprehensive debug information about the license system
    func getDebugInfo(licenseStatus: LicenseStatus, needsLicenseSetup: Bool) -> [String: Any] {
        let deviceInfo = deviceIdentifier.getDeviceInfo()
        let usageAnalytics = usageTracker.getUsageAnalytics()
        
        return [
            "device_info": deviceInfo,
            "usage_analytics": usageAnalytics,
            "license_status": licenseStatus.debugDescription,
            "has_stored_license": secureStorage.hasValidLicense(),
            "has_device_registration": secureStorage.hasDeviceRegistration(),
            "needs_license_setup": needsLicenseSetup
        ]
    }
    
    /// Reset all license data for testing purposes
    func resetForTesting() {
        print("🧪 Resetting license system for testing...")
        
        _ = secureStorage.clearAllData()
        // Usage is managed by the API, not locally
    }
    
    /// Get analytics data for tracking license usage patterns
    func getLicenseAnalytics(licenseStatus: LicenseStatus) -> [String: Any] {
        var analytics: [String: Any] = [
            "license_type": getLicenseType(from: licenseStatus),
            "has_valid_license": secureStorage.hasValidLicense(),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Add usage metrics
        analytics["usage_metrics"] = usageTracker.getUsageAnalytics()
        
        // Add device registration status
        analytics["device_registered"] = secureStorage.hasDeviceRegistration()
        
        return analytics
    }
    
    private func getLicenseType(from status: LicenseStatus) -> String {
        switch status {
        case .licensed:
            return "licensed"
        case .freeTrial:
            return "free_trial"
        case .trialExpired:
            return "trial_expired"
        case .unlicensed:
            return "unlicensed"
        case .unknown:
            return "unknown"
        }
    }
}