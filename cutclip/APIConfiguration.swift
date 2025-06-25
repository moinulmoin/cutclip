//
//  APIConfiguration.swift
//  cutclip
//
//  Created by Moinul Moin on 6/24/25.
//

import Foundation

/// Centralized API configuration for all network services
struct APIConfiguration {

    /// Single source of truth for API base URL
    static var baseURL: String {
        if let envURL = ProcessInfo.processInfo.environment["CUTCLIP_API_BASE_URL"] {
            #if DEBUG
            print("🔧 Using API URL from environment: \(envURL)")
            #endif
            return envURL
        } else {
            let defaultURL = "https://cutclip.moinulmoin.com/api"
            #if DEBUG
            print("🔧 Using default API URL: \(defaultURL)")
            #endif
            return defaultURL
        }
    }

    /// Common API endpoints
    struct Endpoints {
        static let checkDevice = "/users/check-device"
        static let createDevice = "/users/create-device"
        static let updateDevice = "/users/update-device"
        static let decrementCredits = "/users/decrement-free-credits"
        static let validateLicense = "/validate-license"
    }

    /// Common headers for all requests
    static var defaultHeaders: [String: String] {
        return [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    /// Network timeout in seconds
    static let requestTimeout: TimeInterval = 10.0

    /// Create URLRequest with proper timeout and headers
    static func createRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = method
        defaultHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    /// Perform secure network request with certificate pinning when appropriate
    static func performSecureRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let secureNetworking = await SecureNetworking.shared
        if await secureNetworking.shouldUseCertificatePinning(for: url) {
            #if DEBUG
            print("🔒 Using certificate pinning for: \(url.host ?? "unknown")")
            #endif
            return try await secureNetworking.secureDataRequest(for: request)
        } else {
            #if DEBUG
            print("🌐 Using standard networking for: \(url.host ?? "unknown")")
            #endif
            return try await URLSession.shared.data(for: request)
        }
    }
}