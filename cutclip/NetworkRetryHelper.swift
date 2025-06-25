//
//  NetworkRetryHelper.swift
//  cutclip
//
//  Created by Moinul Moin on 6/24/25.
//

import Foundation

struct NetworkRetryHelper {
    
    /// Retry a network operation up to 3 times with exponential backoff
    static func retryOperation<T>(
        maxRetries: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let result = try await operation()
                if attempt > 1 {
                    print("✅ Network operation succeeded on attempt \(attempt)")
                }
                return result
            } catch {
                lastError = error
                print("⚠️ Network operation failed on attempt \(attempt)/\(maxRetries): \(error.localizedDescription)")
                
                // Don't delay after the last attempt
                if attempt < maxRetries {
                    let delay = min(2.0 * Double(attempt), 5.0) // Exponential backoff, max 5 seconds
                    print("🔄 Retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        print("❌ Network operation failed after \(maxRetries) attempts")
        throw lastError ?? NetworkError.maxRetriesExceeded
    }
}

enum NetworkError: Error {
    case maxRetriesExceeded
    
    var localizedDescription: String {
        switch self {
        case .maxRetriesExceeded:
            return "Network operation failed after maximum retries"
        }
    }
}