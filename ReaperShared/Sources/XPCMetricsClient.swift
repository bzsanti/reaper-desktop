import Foundation

/// Client for connecting to the ReaperMetricsService Launch Agent
/// This client provides both callback-based and async methods for fetching metrics
/// Connects via Mach service name to a shared Launch Agent
public final class XPCMetricsClient {

    // MARK: - Properties

    /// The Mach service name (must match Launch Agent plist)
    public let serviceName: String = "com.reaper.metrics"

    /// Current connection to the XPC service
    private var connection: NSXPCConnection?

    /// Lock for thread-safe operations
    private let lock = NSLock()

    /// Whether the client is currently connected
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connection != nil
    }

    /// Error handler called when connection fails or is interrupted
    public var onConnectionError: ((Error) -> Void)?

    /// Handler called when connection is invalidated
    public var onConnectionInvalidated: (() -> Void)?

    // MARK: - Initialization

    public init() {}

    deinit {
        disconnect()
    }

    // MARK: - Connection Management

    /// Create a new XPC connection (for testing/inspection)
    public func createConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: serviceName)
        conn.remoteObjectInterface = createInterface()
        return conn
    }

    /// Create the XPC interface with proper class configuration
    public func createInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)
        configureInterfaceClasses(interface)
        return interface
    }

    /// Connect to the Launch Agent via Mach service
    public func connect() {
        lock.lock()
        defer { lock.unlock() }

        // Don't reconnect if already connected
        guard connection == nil else { return }

        let conn = NSXPCConnection(machServiceName: serviceName)
        conn.remoteObjectInterface = createInterface()

        // Set up handlers
        conn.invalidationHandler = { [weak self] in
            self?.handleInvalidation()
        }

        conn.interruptionHandler = { [weak self] in
            self?.handleInterruption()
        }

        conn.resume()
        connection = conn
    }

    /// Disconnect from the XPC service
    public func disconnect() {
        lock.lock()
        let conn = connection
        connection = nil
        lock.unlock()

        conn?.invalidate()
    }

    // MARK: - Callback-based Methods

    /// Get CPU metrics via callback
    public func getCpuMetrics(completion: @escaping (CpuMetricsData?) -> Void) {
        guard let proxy = getProxy() else {
            completion(nil)
            return
        }

        proxy.getCpuMetrics { metrics, error in
            if let error = error {
                self.onConnectionError?(error)
            }
            completion(metrics)
        }
    }

    /// Get disk metrics via callback
    public func getDiskMetrics(completion: @escaping (DiskMetricsData?) -> Void) {
        guard let proxy = getProxy() else {
            completion(nil)
            return
        }

        proxy.getDiskMetrics { metrics, error in
            if let error = error {
                self.onConnectionError?(error)
            }
            completion(metrics)
        }
    }

    /// Get temperature via callback
    public func getTemperature(completion: @escaping (TemperatureData?) -> Void) {
        guard let proxy = getProxy() else {
            completion(nil)
            return
        }

        proxy.getTemperature { temp, error in
            if let error = error {
                self.onConnectionError?(error)
            }
            completion(temp)
        }
    }

    /// Ping the service via callback
    public func ping(completion: @escaping (Bool) -> Void) {
        guard let proxy = getProxy() else {
            completion(false)
            return
        }

        proxy.ping { result in
            completion(result)
        }
    }

    // MARK: - Async Methods

    /// Timeout for XPC calls in seconds
    private static let xpcTimeout: TimeInterval = 2.0

    /// Get CPU metrics asynchronously with timeout
    public func getCpuMetricsAsync() async -> CpuMetricsData? {
        await withTimeoutOptional(seconds: Self.xpcTimeout) { [weak self] in
            await withCheckedContinuation { continuation in
                self?.getCpuMetrics { metrics in
                    continuation.resume(returning: metrics)
                } ?? continuation.resume(returning: nil)
            }
        }
    }

    /// Get disk metrics asynchronously with timeout
    public func getDiskMetricsAsync() async -> DiskMetricsData? {
        await withTimeoutOptional(seconds: Self.xpcTimeout) { [weak self] in
            await withCheckedContinuation { continuation in
                self?.getDiskMetrics { metrics in
                    continuation.resume(returning: metrics)
                } ?? continuation.resume(returning: nil)
            }
        }
    }

    /// Get temperature asynchronously with timeout
    public func getTemperatureAsync() async -> TemperatureData? {
        await withTimeoutOptional(seconds: Self.xpcTimeout) { [weak self] in
            await withCheckedContinuation { continuation in
                self?.getTemperature { temp in
                    continuation.resume(returning: temp)
                } ?? continuation.resume(returning: nil)
            }
        }
    }

    /// Ping the service asynchronously with timeout
    public func pingAsync() async -> Bool {
        let result = await withTimeoutBool(seconds: Self.xpcTimeout) { [weak self] in
            await withCheckedContinuation { continuation in
                self?.ping { result in
                    continuation.resume(returning: result)
                } ?? continuation.resume(returning: false)
            }
        }
        return result
    }

    /// Execute an async operation with a timeout, returning optional
    private func withTimeoutOptional<T>(seconds: TimeInterval, operation: @escaping () async -> T?) async -> T? {
        let result: T? = await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            // Return the first completed result
            for await taskResult in group {
                group.cancelAll()
                return taskResult
            }
            return nil
        }
        return result
    }

    /// Execute an async operation with a timeout, returning Bool
    private func withTimeoutBool(seconds: TimeInterval, operation: @escaping () async -> Bool) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await operation()
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }

            // Return the first completed result
            for await taskResult in group {
                group.cancelAll()
                return taskResult
            }
            return false
        }
    }

    // MARK: - Private Methods

    /// Get a proxy to the remote object
    private func getProxy() -> ReaperMetricsProtocol? {
        lock.lock()
        let conn = connection
        lock.unlock()

        guard let conn = conn else { return nil }

        return conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.onConnectionError?(error)
        } as? ReaperMetricsProtocol
    }

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
    private func handleInvalidation() {
        lock.lock()
        connection = nil
        lock.unlock()

        onConnectionInvalidated?()
    }

    /// Handle connection interruption
    private func handleInterruption() {
        // Connection was interrupted but may recover
        // The proxy will return errors for pending calls
    }
}
