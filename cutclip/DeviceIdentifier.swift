//
//  DeviceIdentifier.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation
import IOKit
import CommonCrypto

class DeviceIdentifier {
    nonisolated(unsafe) static let shared = DeviceIdentifier()
    private init() {}

    /// Get a unique, persistent device identifier for this Mac
    /// This ID survives OS reinstalls and app reinstalls
    func getDeviceID() -> String {
        // Try multiple methods to ensure we get a stable ID
        if let cachedID = getCachedDeviceID() {
            return cachedID
        }

        let deviceID = generateDeviceID()
        cacheDeviceID(deviceID)
        return deviceID
    }

    private func generateDeviceID() -> String {
        var components: [String] = []

        // 1. Hardware UUID (most reliable)
        if let hardwareUUID = getHardwareUUID() {
            components.append(hardwareUUID)
        }

        // 2. Serial Number (backup)
        if let serialNumber = getSerialNumber() {
            components.append(serialNumber)
        }

        // 3. MAC Address (additional uniqueness)
        if let macAddress = getMACAddress() {
            components.append(macAddress)
        }

        // Combine and hash for consistency
        let combined = components.joined(separator: "-")
        return combined.sha256()
    }

    // MARK: - Hardware Identifiers

    private func getHardwareUUID() -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, matching)

        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        let key = "IOPlatformUUID"
        if let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return uuid
        }

        return nil
    }

    private func getSerialNumber() -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, matching)

        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        let key = "IOPlatformSerialNumber"
        if let serial = IORegistryEntryCreateCFProperty(
            platformExpert,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return serial
        }

        return nil
    }

    private func getMACAddress() -> String? {
        var iterator: io_iterator_t = 0

        // Create a matching dictionary to find network interfaces
        let matchingDict = IOServiceMatching("IOEthernetInterface") as NSMutableDictionary
        matchingDict["IOPropertyMatch"] = ["IOPrimaryInterface": true]

        // Use the matching dictionary to get the services
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        // Iterate over the services
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var parentService: io_object_t = 0

            // The MAC address is on the parent service (IOEthernetController)
            if IORegistryEntryGetParentEntry(service, "IOEthernetController", &parentService) == kIOReturnSuccess {
                defer { IOObjectRelease(parentService) }

                if let macAddressData = IORegistryEntryCreateCFProperty(parentService, "IOMACAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                    let macAddressString = macAddressData.map { String(format: "%02x", $0) }.joined(separator: ":")
                    return macAddressString
                }
            }

            // Get the next service
            service = IOIteratorNext(iterator)
        }

        return nil
    }

    // MARK: - Caching

    private func getCachedDeviceID() -> String? {
        return UserDefaults.standard.string(forKey: "CutClip_DeviceID")
    }

    private func cacheDeviceID(_ deviceID: String) {
        UserDefaults.standard.set(deviceID, forKey: "CutClip_DeviceID")
    }

    // MARK: - Device Info

    func getDeviceInfo() -> [String: String] {
        return [
            "device_id": getDeviceID(),
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "model": getMacModel(),
            "architecture": getArchitecture()
        ]
    }

    private func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)

        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)

        // Convert CChar (Int8) to UInt8 for modern UTF8 decoding
        let uint8Model = model.map { UInt8(bitPattern: $0) }
        if let nullIndex = uint8Model.firstIndex(of: 0) {
            return String(decoding: uint8Model[..<nullIndex], as: UTF8.self)
        }
        return String(decoding: uint8Model, as: UTF8.self)
    }

    private func getArchitecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
    }
}

// MARK: - String Hashing Extension

extension String {
    func sha256() -> String {
        guard let data = self.data(using: .utf8) else { return self }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
