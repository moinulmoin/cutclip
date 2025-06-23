//
//  SecureStorage.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation
import Security

class SecureStorage {
    nonisolated(unsafe) static let shared = SecureStorage()
    private init() {}

    private let serviceName = "com.cutclip.license"
    private let licenseAccount = "license_key"
    private let deviceAccount = "device_registration"

    // MARK: - License Storage

    func storeLicense(_ licenseKey: String, deviceID: String) -> Bool {
        let licenseData = [
            "license_key": licenseKey,
            "device_id": deviceID,
            "activated_at": ISO8601DateFormatter().string(from: Date())
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: licenseData) else {
            return false
        }

        return storeData(jsonData, account: licenseAccount)
    }

    func retrieveLicense() -> (key: String, deviceID: String, activatedAt: Date?)? {
        guard let data = retrieveData(account: licenseAccount),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let licenseKey = json["license_key"],
              let deviceID = json["device_id"] else {
            return nil
        }

        let activatedAt = json["activated_at"].flatMap {
            ISO8601DateFormatter().date(from: $0)
        }

        return (key: licenseKey, deviceID: deviceID, activatedAt: activatedAt)
    }

    func deleteLicense() -> Bool {
        return deleteData(account: licenseAccount)
    }

    // MARK: - Device Registration Storage

    func storeDeviceRegistration(_ registrationData: [String: Any]) -> Bool {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: registrationData) else {
            return false
        }

        return storeData(jsonData, account: deviceAccount)
    }

    func retrieveDeviceRegistration() -> [String: Any]? {
        guard let data = retrieveData(account: deviceAccount),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    func deleteDeviceRegistration() -> Bool {
        return deleteData(account: deviceAccount)
    }

    // MARK: - Keychain Operations

    private func storeData(_ data: Data, account: String) -> Bool {
        // First, delete any existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func retrieveData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteData(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Utility Methods

    func clearAllData() -> Bool {
        let licenseDeleted = deleteLicense()
        let deviceDeleted = deleteDeviceRegistration()
        return licenseDeleted && deviceDeleted
    }

    func hasValidLicense() -> Bool {
        return retrieveLicense() != nil
    }

    func hasDeviceRegistration() -> Bool {
        return retrieveDeviceRegistration() != nil
    }
}