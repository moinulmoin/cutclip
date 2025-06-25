//
//  SecureNetworking.swift
//  cutclip
//
//  Created by Claude on 6/25/25.
//

import Foundation
import Network
import CommonCrypto

/// Secure networking helper with certificate pinning for API endpoints
@MainActor
final class SecureNetworking: ObservableObject, Sendable {
    static let shared = SecureNetworking()

    private lazy var secureSession: URLSession = createSecureSession()

    private init() {}

    // Expected certificate hashes for cutclip.moinulmoin.com
    // CRITICAL: This must be configured with actual certificate SHA-256 fingerprints before production release
    // Certificate pinning is currently DISABLED due to empty hash set
    private let pinnedCertificateHashes: Set<String> = [
        // TODO: Replace with actual certificate SHA-256 fingerprints for your domain
        // To get certificate fingerprint:
        // openssl s_client -connect cutclip.moinulmoin.com:443 -servername cutclip.moinulmoin.com </dev/null 2>/dev/null | openssl x509 -fingerprint -sha256 -noout
        // Example format: "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456"
        // Add your production certificate hashes here before release
    ]

    /// Create URLSession with certificate pinning
    private func createSecureSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0

        let session = URLSession(
            configuration: config,
            delegate: SecureURLSessionDelegate(pinnedHashes: pinnedCertificateHashes),
            delegateQueue: nil
        )

        return session
    }

    /// Perform secure data request with certificate pinning
    func secureDataRequest(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await secureSession.data(for: request)
    }

    /// Check if we should use certificate pinning for this URL
    func shouldUseCertificatePinning(for url: URL) -> Bool {
        guard let host = url.host else { return false }

        // Only use certificate pinning for production API
        let productionHosts = ["cutclip.moinulmoin.com", "api.cutclip.com"]
        return productionHosts.contains(host)
    }
}

/// URLSessionDelegate for certificate pinning
private final class SecureURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let pinnedHashes: Set<String>

    init(pinnedHashes: Set<String>) {
        self.pinnedHashes = pinnedHashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only perform certificate pinning for server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            print("❌ No server trust available for certificate pinning")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get the server certificate using modern API (macOS 14+ minimum)
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let serverCertificate = certificateChain.first else {
            print("❌ No server certificate available for pinning")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get certificate data and compute SHA-256 hash
        let serverCertData = SecCertificateCopyData(serverCertificate)
        let data = CFDataGetBytePtr(serverCertData)
        let size = CFDataGetLength(serverCertData)

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(data, CC_LONG(size), &hash)

        let serverCertHash = hash.map { String(format: "%02x", $0) }.joined()

                // Check if we have any pinned hashes configured
        if pinnedHashes.isEmpty {
            #if DEBUG
            print("⚠️ Certificate pinning is disabled - no hashes configured")
            print("🔓 Falling back to default certificate validation")
            #endif
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Check if server certificate hash matches our pinned hashes
        if pinnedHashes.contains(serverCertHash) {
            #if DEBUG
            print("✅ Certificate pinning validation passed")
            #endif
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            #if DEBUG
            print("❌ Certificate pinning validation failed - unknown certificate")
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}