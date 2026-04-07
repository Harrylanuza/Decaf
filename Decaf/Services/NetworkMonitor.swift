import Network
import Observation

/// Observes the device's network path and publishes `isConnected`.
///
/// Uses `NWPathMonitor` (event-driven, not polling) so battery impact
/// is negligible.  Inject into the SwiftUI environment at the app root
/// and read with `@Environment(NetworkMonitor.self)` in any view.
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "dev.decaf.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
