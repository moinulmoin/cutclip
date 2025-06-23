//
//  DeviceIdentifier.swift
//  cutclip
//
//  Created by Moinul Moin on 6/21/25.
//

import Foundation
import IOKit

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
        // Get primary network interface MAC address
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        task.arguments = ["en0"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Extract MAC address using regex
            let macPattern = #"ether ([a-f0-9:]{17})"#
            let regex = try NSRegularExpression(pattern: macPattern)
            let range = NSRange(output.startIndex..<output.endIndex, in: output)

            if let match = regex.firstMatch(in: output, range: range) {
                let macRange = Range(match.range(at: 1), in: output)!
                return String(output[macRange])
            }
        } catch {
            print("Failed to get MAC address: \(error)")
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

// Import CommonCrypto for hashing
import CommonCrypto
