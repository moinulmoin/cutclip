import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = true
    @Published var connectionType: ConnectionType = .unknown
    @Published var showNetworkAlert = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
        case noConnection
    }
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasConnected = self?.isConnected ?? true
                self?.isConnected = path.status == .satisfied
                
                // Determine connection type
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) {
                        self?.connectionType = .wifi
                    } else if path.usesInterfaceType(.cellular) {
                        self?.connectionType = .cellular
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        self?.connectionType = .wiredEthernet
                    } else {
                        self?.connectionType = .unknown
                    }
                } else {
                    self?.connectionType = .noConnection
                }
                
                // Only show alert when connection is lost
                if wasConnected && self?.isConnected == false {
                    self?.showNetworkAlert = true
                    print("📡 Network disconnected")
                } else if !wasConnected && self?.isConnected == true {
                    self?.showNetworkAlert = false
                    print("📡 Network reconnected via \(self?.connectionType ?? .unknown)")
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    func requireNetwork() -> Bool {
        if !isConnected {
            showNetworkAlert = true
            return false
        }
        return true
    }
    
    /// Differentiates between no network and server unreachable
    func diagnoseNetworkError(_ error: Error) -> NetworkDiagnosis {
        // First check device connectivity
        guard isConnected else {
            return .noInternetConnection
        }
        
        // Check for URLError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .noInternetConnection
            case .cannotConnectToHost, .cannotFindHost:
                return .serverUnreachable
            case .timedOut:
                return .serverTimeout
            case .networkConnectionLost:
                return .connectionLost
            default:
                return .serverError(urlError.localizedDescription)
            }
        }
        
        // Check error description for common patterns
        let errorDesc = error.localizedDescription.lowercased()
        if errorDesc.contains("network") || errorDesc.contains("connection") {
            return isConnected ? .serverUnreachable : .noInternetConnection
        }
        
        return .unknownError(error.localizedDescription)
    }
    
    deinit {
        monitor.cancel()
    }
}

enum NetworkDiagnosis {
    case noInternetConnection
    case serverUnreachable
    case serverTimeout
    case connectionLost
    case serverError(String)
    case unknownError(String)
    
    var userMessage: String {
        switch self {
        case .noInternetConnection:
            return "No internet connection. CutClip requires internet to initialize. Please check your network settings."
        case .serverUnreachable:
            return "Could not connect to CutClip servers."
        case .serverTimeout:
            return "Server request timed out. Please check your connection and try again."
        case .connectionLost:
            return "Connection was lost. Please check your network and retry."
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknownError(let message):
            return "Network error: \(message)"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .noInternetConnection, .serverUnreachable, .serverTimeout, .connectionLost:
            return true
        case .serverError, .unknownError:
            return false
        }
    }
}