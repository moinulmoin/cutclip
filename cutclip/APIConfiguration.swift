//
//  APIConfiguration.swift
//  cutclip
//
//  Created by Moinul Moin on 6/24/25.
//

import Foundation
import CommonCrypto

/// Centralized API configuration for all network services
///
/// SECURITY FEATURES:
/// - API Key Authentication: Automatically adds X-API-Key header to all requests
/// - Request Signing: HMAC-SHA256 signatures with timestamps prevent replay attacks
/// - Secure Storage: API credentials stored in macOS Keychain
///
/// USAGE:
/// ```swift
/// // Store API credentials (typically during app setup)
/// APIConfiguration.storeAPICredentials(apiKey: "your-api-key", apiSecret: "your-secret")
///
/// // Check if credentials exist
/// if APIConfiguration.hasAPICredentials() {
///     // Make authenticated requests
/// }
///
/// // Delete credentials (e.g., on logout)
/// APIConfiguration.deleteAPICredentials()
/// ```
struct APIConfiguration {
    
    /// API Key storage key for SecureStorage
    private static let apiKeyAccount = "api_key"
    private static let apiSecretAccount = "api_secret"

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
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        
        // Add API key if available
        if let apiKey = getAPIKey() {
            headers["X-API-Key"] = apiKey
        }
        
        return headers
    }

    /// Network timeout in seconds
    static let requestTimeout: TimeInterval = 10.0

    /// Create URLRequest with proper timeout, headers, and request signing
    static func createRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.httpBody = body
        
        // Add default headers
        defaultHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add request signature if API secret is available
        if let apiSecret = getAPISecret() {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
            
            // Create signature from request body + timestamp
            let dataToSign = (body ?? Data()) + timestamp.data(using: .utf8)!
            if let signature = createHMACSignature(data: dataToSign, secret: apiSecret) {
                request.setValue(signature, forHTTPHeaderField: "X-Signature")
            }
        }
        
        return request
    }

    /// Perform secure network request with enhanced security
    static func performSecureRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let secureNetworking = await SecureNetworking.shared
        if await secureNetworking.shouldUseEnhancedSecurity(for: url) {
            #if DEBUG
            print("🔒 Using enhanced security for: \(url.host ?? "unknown")")
            #endif
            return try await secureNetworking.secureDataRequest(for: request)
        } else {
            #if DEBUG
            print("🌐 Using standard networking for: \(url.host ?? "unknown")")
            #endif
            return try await URLSession.shared.data(for: request)
        }
    }
    
    // MARK: - API Key Management
    
    /// Store API credentials in keychain
    static func storeAPICredentials(apiKey: String, apiSecret: String) -> Bool {
        let storage = SecureStorage.shared
        
        // Store API key
        let keyStored = storage.storeData(
            apiKey.data(using: .utf8)!,
            account: apiKeyAccount
        )
        
        // Store API secret
        let secretStored = storage.storeData(
            apiSecret.data(using: .utf8)!,
            account: apiSecretAccount
        )
        
        return keyStored && secretStored
    }
    
    /// Retrieve API key from keychain
    private static func getAPIKey() -> String? {
        guard let data = SecureStorage.shared.retrieveData(account: apiKeyAccount),
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        return apiKey
    }
    
    /// Retrieve API secret from keychain
    private static func getAPISecret() -> String? {
        guard let data = SecureStorage.shared.retrieveData(account: apiSecretAccount),
              let apiSecret = String(data: data, encoding: .utf8) else {
            return nil
        }
        return apiSecret
    }
    
    /// Delete API credentials from keychain
    static func deleteAPICredentials() -> Bool {
        let storage = SecureStorage.shared
        let keyDeleted = storage.deleteData(account: apiKeyAccount)
        let secretDeleted = storage.deleteData(account: apiSecretAccount)
        return keyDeleted && secretDeleted
    }
    
    /// Check if API credentials are stored
    static func hasAPICredentials() -> Bool {
        return getAPIKey() != nil && getAPISecret() != nil
    }
    
    // MARK: - Request Signing
    
    /// Create HMAC-SHA256 signature
    private static func createHMACSignature(data: Data, secret: String) -> String? {
        guard let secretData = secret.data(using: .utf8) else { return nil }
        
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        data.withUnsafeBytes { dataBytes in
            secretData.withUnsafeBytes { secretBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    secretBytes.baseAddress,
                    secretData.count,
                    dataBytes.baseAddress,
                    data.count,
                    &hmac
                )
            }
        }
        
        // Convert to hex string
        return hmac.map { String(format: "%02x", $0) }.joined()
    }
}