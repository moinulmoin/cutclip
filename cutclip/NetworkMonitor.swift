import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = true
    @Published var showNetworkAlert = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasConnected = self?.isConnected ?? true
                self?.isConnected = path.status == .satisfied
                
                if !wasConnected && self?.isConnected == true {
                    self?.showNetworkAlert = false
                } else if wasConnected && self?.isConnected == false {
                    self?.showNetworkAlert = true
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    func requireNetwork() {
        if !isConnected {
            showNetworkAlert = true
        }
    }
    
    deinit {
        monitor.cancel()
    }
}