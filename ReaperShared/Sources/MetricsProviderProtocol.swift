import Foundation

/// Protocol for metrics providers
/// This abstracts the source of metrics data, allowing for:
/// - RustMetricsProvider: Real data from Rust FFI
/// - MockMetricsProvider: Test data for unit tests
/// - FallbackMetricsProvider: Local fallback when XPC unavailable
public protocol MetricsProviderProtocol: AnyObject {

    /// Initialize the provider and prepare for metrics collection
    /// Must be called before any other methods
    func initialize()

    /// Refresh the metrics data
    /// Should be called periodically to update cached values
    func refresh()

    /// Get current CPU metrics
    /// - Returns: CPU metrics or nil if unavailable
    func getCpuMetrics() -> CpuMetricsData?

    /// Get current disk metrics for primary disk
    /// - Returns: Disk metrics or nil if unavailable
    func getDiskMetrics() -> DiskMetricsData?

    /// Get current CPU temperature
    /// - Returns: Temperature data or nil if unavailable
    func getTemperature() -> TemperatureData?

    /// Cleanup resources and prepare for shutdown
    func cleanup()
}

// MARK: - Provider State

/// State of a metrics provider
public enum MetricsProviderState {
    case uninitialized
    case initializing
    case ready
    case error(Error)
    case stopped
}

// MARK: - Base Implementation

/// Base class providing common functionality for metrics providers
/// Subclasses should override the fetch methods
open class BaseMetricsProvider: MetricsProviderProtocol {

    /// Current state of the provider
    public private(set) var state: MetricsProviderState = .uninitialized

    /// Lock for thread-safe operations
    private let lock = NSLock()

    /// Cached metrics
    private var cachedCpuMetrics: CpuMetricsData?
    private var cachedDiskMetrics: DiskMetricsData?
    private var cachedTemperature: TemperatureData?

    /// Time of last refresh
    private var lastRefreshTime: Date?

    /// Minimum interval between refreshes (in seconds)
    public var minimumRefreshInterval: TimeInterval = 0.5

    public init() {}

    // MARK: - MetricsProviderProtocol

    public func initialize() {
        lock.lock()
        defer { lock.unlock() }

        guard case .uninitialized = state else { return }

        state = .initializing

        // Subclasses should override to perform actual initialization
        performInitialization()

        state = .ready
    }

    public func refresh() {
        lock.lock()
        defer { lock.unlock() }

        guard case .ready = state else { return }

        // Check minimum refresh interval
        if let lastTime = lastRefreshTime,
           Date().timeIntervalSince(lastTime) < minimumRefreshInterval {
            return
        }

        // Subclasses should override to perform actual refresh
        performRefresh()

        lastRefreshTime = Date()
    }

    public func getCpuMetrics() -> CpuMetricsData? {
        lock.lock()
        defer { lock.unlock() }

        guard case .ready = state else { return nil }

        // Return cached value or fetch new
        if let cached = cachedCpuMetrics {
            return cached
        }

        let metrics = fetchCpuMetrics()
        cachedCpuMetrics = metrics
        return metrics
    }

    public func getDiskMetrics() -> DiskMetricsData? {
        lock.lock()
        defer { lock.unlock() }

        guard case .ready = state else { return nil }

        if let cached = cachedDiskMetrics {
            return cached
        }

        let metrics = fetchDiskMetrics()
        cachedDiskMetrics = metrics
        return metrics
    }

    public func getTemperature() -> TemperatureData? {
        lock.lock()
        defer { lock.unlock() }

        guard case .ready = state else { return nil }

        if let cached = cachedTemperature {
            return cached
        }

        let temp = fetchTemperature()
        cachedTemperature = temp
        return temp
    }

    public func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        performCleanup()

        cachedCpuMetrics = nil
        cachedDiskMetrics = nil
        cachedTemperature = nil
        lastRefreshTime = nil
        state = .stopped
    }

    // MARK: - Override Points

    /// Override to perform initialization
    open func performInitialization() {
        // Subclasses should override
    }

    /// Override to perform refresh
    open func performRefresh() {
        // Clear cache on refresh
        cachedCpuMetrics = nil
        cachedDiskMetrics = nil
        cachedTemperature = nil
    }

    /// Override to fetch CPU metrics
    open func fetchCpuMetrics() -> CpuMetricsData? {
        return nil
    }

    /// Override to fetch disk metrics
    open func fetchDiskMetrics() -> DiskMetricsData? {
        return nil
    }

    /// Override to fetch temperature
    open func fetchTemperature() -> TemperatureData? {
        return nil
    }

    /// Override to perform cleanup
    open func performCleanup() {
        // Subclasses should override
    }
}
