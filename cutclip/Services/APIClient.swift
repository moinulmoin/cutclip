//
//  APIClient.swift
//  cutclip
//
//  Created by Assistant on 7/2/25.
//

import Foundation

/// Generic API client with built-in retry logic
public actor APIClient {
    private let maxRetries = 3
    private let baseDelay = 2.0
    private let maxDelay = 5.0
    
    public init() {}
    
    /// Perform a request with automatic retry logic
    public func performRequest<T: Decodable & Sendable>(
        _ request: URLRequest,
        expecting type: T.Type,
        successCode: Int = 200,
        onRetry: (@Sendable (Int, Error) -> Void)? = nil
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await APIConfiguration.performSecureRequest(request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                if httpResponse.statusCode == successCode {
                    return try JSONDecoder().decode(T.self, from: data)
                } else {
                    throw APIError.serverError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                onRetry?(attempt, error)
                
                if attempt < maxRetries {
                    let delay = min(baseDelay * Double(attempt), maxDelay)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? APIError.unknownError
    }
    
    /// Perform a request that returns optional data in the response
    public func performRequestWithOptionalData<T: Decodable & Sendable>(
        _ request: URLRequest,
        responseType: T.Type,
        successCode: Int = 200,
        onRetry: (@Sendable (Int, Error) -> Void)? = nil
    ) async throws -> (response: T, data: Any?) {
        let response: T = try await performRequest(request, expecting: responseType, successCode: successCode, onRetry: onRetry)
        
        // Extract data field if it exists using mirror reflection
        let mirror = Mirror(reflecting: response)
        for child in mirror.children {
            if child.label == "data" {
                return (response: response, data: child.value)
            }
        }
        
        return (response: response, data: nil)
    }
    
    /// Perform a simple request without expecting specific response type
    public func performSimpleRequest(
        _ request: URLRequest,
        successCode: Int = 200,
        onRetry: (@Sendable (Int, Error) -> Void)? = nil
    ) async throws -> Data {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await APIConfiguration.performSecureRequest(request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                if httpResponse.statusCode == successCode {
                    return data
                } else {
                    throw APIError.serverError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                onRetry?(attempt, error)
                
                if attempt < maxRetries {
                    let delay = min(baseDelay * Double(attempt), maxDelay)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? APIError.unknownError
    }
    
    /// Perform a request with custom status code handling
    public func performRequestWithCustomHandling<T: Decodable & Sendable>(
        _ request: URLRequest,
        expecting type: T.Type,
        onRetry: (@Sendable (Int, Error) -> Void)? = nil,
        shouldRetry: (@Sendable (Error) -> Bool)? = nil,
        handleResponse: (@Sendable (Int, Data) async throws -> T)? = nil
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await APIConfiguration.performSecureRequest(request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                // Use custom handler if provided
                if let handler = handleResponse {
                    return try await handler(httpResponse.statusCode, data)
                }
                
                // Default handling
                if httpResponse.statusCode == 200 {
                    return try JSONDecoder().decode(T.self, from: data)
                } else {
                    throw APIError.serverError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                
                // Check if we should retry this error
                if let shouldRetry = shouldRetry, !shouldRetry(error) {
                    throw error
                }
                
                onRetry?(attempt, error)
                
                if attempt < maxRetries {
                    let delay = min(baseDelay * Double(attempt), maxDelay)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? APIError.unknownError
    }
}

/// API-specific errors
public enum APIError: LocalizedError {
    case invalidResponse
    case serverError(Int)
    case unknownError
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}