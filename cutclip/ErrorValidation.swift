//
//  ErrorValidation.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import Foundation

/// System validation and error checking utilities
/// Separates validation logic from error presentation
enum ErrorValidation {
    
    /// Check if sufficient disk space is available
    /// - Parameter requiredMB: Required space in megabytes (default: 500MB)
    /// - Throws: AppError.diskSpace if insufficient space
    static func checkDiskSpace(requiredMB: Int = 500) throws {
        guard let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw ErrorFactory.fileSystemError("Cannot access Downloads directory")
        }
        
        do {
            let resourceValues = try downloadsPath.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacity {
                let availableMB = availableCapacity / (1024 * 1024)
                if availableMB < requiredMB {
                    throw ErrorFactory.diskSpaceError(requiredMB: requiredMB, availableMB: availableMB)
                }
            }
        } catch {
            if error is AppError {
                throw error
            } else {
                throw ErrorFactory.fileSystemError("Unable to check disk space: \(error.localizedDescription)")
            }
        }
    }
    
    /// Check network connectivity by attempting to reach YouTube
    /// - Throws: AppError.network if connection fails
    static func checkNetworkConnectivity() async throws {
        let url = URL(string: "https://www.youtube.com")!
        let request = URLRequest(url: url, timeoutInterval: 10.0)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    throw ErrorFactory.serverError()
                }
            }
        } catch {
            if error is AppError {
                throw error
            } else {
                throw ErrorFactory.noInternetError()
            }
        }
    }
}