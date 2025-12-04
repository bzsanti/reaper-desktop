import Foundation
import ReaperShared

/// XPC Service Delegate that handles incoming connections
/// This delegate configures each connection with the proper interface and exported object
public final class ReaperMetricsServiceDelegate: NSObject, NSXPCListenerDelegate {

    // MARK: - Properties

    /// Factory for creating metrics providers
    /// Each connection gets its own provider instance
    private let providerFactory: MetricsProviderFactory

    /// Track active connections for cleanup
    private var activeConnections = Set<NSXPCConnection>()
    private let connectionsLock = NSLock()

    // MARK: - Initialization

    /// Initialize with a provider factory
    /// - Parameter providerFactory: Factory that creates MetricsProviderProtocol instances
    public init(providerFactory: @escaping MetricsProviderFactory) {
        self.providerFactory = providerFactory
        super.init()
    }

    /// Convenience initializer with default mock provider (for testing)
    public override convenience init() {
        // Default to a simple mock for testing
        self.init(providerFactory: { MockTestProvider() })
    }

    // MARK: - NSXPCListenerDelegate

    /// Called when a new client wants to connect
    /// - Parameters:
    ///   - listener: The listener that received the connection request
    ///   - newConnection: The new connection to configure
    /// - Returns: true to accept the connection, false to reject
    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // Configure the exported interface
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)
        configureInterfaceClasses(interface)
        newConnection.exportedInterface = interface

        // Create and set the exported object with a provider from the factory
        let provider = providerFactory()
        let exporter = ReaperMetricsExporter(provider: provider)
        newConnection.exportedObject = exporter

        // Set connection handlers
        newConnection.invalidationHandler = { [weak self] in
            self?.handleConnectionInvalidation(newConnection)
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.handleConnectionInterruption(newConnection)
        }

        // Track the connection
        connectionsLock.lock()
        activeConnections.insert(newConnection)
        connectionsLock.unlock()

        // Resume the connection to start receiving messages
        newConnection.resume()

        return true
    }

    // MARK: - Private Methods

    /// Configure allowed classes for the XPC interface
    private func configureInterfaceClasses(_ interface: NSXPCInterface) {
        // NSSet bridging to Set<AnyHashable> is safe for class types
        // Configure getCpuMetrics reply
        let cpuClasses = NSSet(objects: CpuMetricsData.self, NSError.self) as! Set<AnyHashable>
        interface.setClasses(
            cpuClasses,
            for: #selector(ReaperMetricsProtocol.getCpuMetrics(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // Configure getDiskMetrics reply
        let diskClasses = NSSet(objects: DiskMetricsData.self, NSError.self) as! Set<AnyHashable>
        interface.setClasses(
            diskClasses,
            for: #selector(ReaperMetricsProtocol.getDiskMetrics(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // Configure getTemperature reply
        let tempClasses = NSSet(objects: TemperatureData.self, NSError.self) as! Set<AnyHashable>
        interface.setClasses(
            tempClasses,
            for: #selector(ReaperMetricsProtocol.getTemperature(reply:)),
            argumentIndex: 0,
            ofReply: true
        )
    }

    /// Handle connection invalidation
    private func handleConnectionInvalidation(_ connection: NSXPCConnection) {
        connectionsLock.lock()
        activeConnections.remove(connection)
        connectionsLock.unlock()
    }

    /// Handle connection interruption
    private func handleConnectionInterruption(_ connection: NSXPCConnection) {
        // Connection was interrupted but may reconnect
        // Log this event in production
    }

    // MARK: - Cleanup

    /// Invalidate all active connections
    public func invalidateAllConnections() {
        connectionsLock.lock()
        let connections = activeConnections
        activeConnections.removeAll()
        connectionsLock.unlock()

        for connection in connections {
            connection.invalidate()
        }
    }
}

// MARK: - Mock Provider for Testing

/// Simple mock provider for testing purposes
/// Returns static test data without requiring FFI
public final class MockTestProvider: MetricsProviderProtocol {
    private var initialized = false

    public init() {}

    public func initialize() {
        initialized = true
    }

    public func refresh() {
        // No-op for mock
    }

    public func getCpuMetrics() -> CpuMetricsData? {
        guard initialized else { return nil }
        return CpuMetricsData(
            totalUsage: 25.0,
            coreCount: 8,
            loadAverage1: 2.0,
            loadAverage5: 1.5,
            loadAverage15: 1.0,
            frequencyMHz: 3000
        )
    }

    public func getDiskMetrics() -> DiskMetricsData? {
        guard initialized else { return nil }
        return DiskMetricsData(
            mountPoint: "/",
            name: "Test Disk",
            totalBytes: 500_000_000_000,
            availableBytes: 250_000_000_000,
            usedBytes: 250_000_000_000,
            usagePercent: 50.0
        )
    }

    public func getTemperature() -> TemperatureData? {
        guard initialized else { return nil }
        return TemperatureData(cpuTemperature: 45.0, isSimulated: true)
    }

    public func cleanup() {
        initialized = false
    }
}
