import Foundation

/// MetricsManager provides a unified interface for system metrics
/// It first tries XPC service and falls back to local provider if unavailable
public final class MetricsManager {

    // MARK: - Properties

    /// XPC client for connecting to the metrics service
    public let xpcClient: XPCMetricsClient

    /// Fallback provider for when XPC is unavailable
    public let fallbackProvider: MetricsProviderProtocol

    /// Lock for thread-safe operations
    private let lock = NSLock()

    /// Whether currently connected to XPC service
    private var _isXPCConnected: Bool = false
    public var isXPCConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isXPCConnected
    }

    /// Whether currently using fallback provider
    private var _isUsingFallback: Bool = false
    public var isUsingFallback: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isUsingFallback
    }

    // MARK: - Configuration

    /// Whether to automatically fall back when XPC fails
    public var enableFallbackOnFailure: Bool = true

    /// Whether to retry XPC connection after using fallback
    public var retryXPCAfterFallback: Bool = true

    /// Interval in seconds between XPC retry attempts
    public var retryIntervalSeconds: TimeInterval = 30.0

    /// Force using fallback (for testing)
    public var forceUseFallback: Bool = false

    // MARK: - Event Handlers

    /// Called when XPC connection is established
    public var onXPCConnected: (() -> Void)?

    /// Called when XPC connection fails
    public var onXPCDisconnected: (() -> Void)?

    /// Called when fallback mode is activated
    public var onFallbackActivated: (() -> Void)?

    // MARK: - Private State

    private var retryTimer: Timer?
    private var fallbackInitialized = false

    // MARK: - Initialization

    public init(
        xpcClient: XPCMetricsClient = XPCMetricsClient(),
        fallbackProvider: MetricsProviderProtocol = FallbackMetricsProvider()
    ) {
        self.xpcClient = xpcClient
        self.fallbackProvider = fallbackProvider

        // Set up XPC error handling
        xpcClient.onConnectionError = { [weak self] _ in
            self?.handleXPCError()
        }

        xpcClient.onConnectionInvalidated = { [weak self] in
            self?.handleXPCDisconnected()
        }
    }

    deinit {
        cleanup()
    }

    // MARK: - Lifecycle

    /// Start the metrics manager and attempt XPC connection
    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !forceUseFallback else {
            activateFallback()
            return
        }

        xpcClient.connect()
        _isXPCConnected = xpcClient.isConnected
    }

    /// Clean up resources
    public func cleanup() {
        lock.lock()
        retryTimer?.invalidate()
        retryTimer = nil
        _isXPCConnected = false
        lock.unlock()

        xpcClient.disconnect()
        fallbackProvider.cleanup()
    }

    // MARK: - Metrics Methods

    /// Get CPU metrics from either XPC or fallback
    public func getCpuMetrics() async -> CpuMetricsData? {
        if forceUseFallback {
            activateFallback()
            return getFallbackCpuMetrics()
        }

        if isUsingFallback && !shouldRetryXPC() {
            return getFallbackCpuMetrics()
        }

        // Try XPC first
        if let metrics = await xpcClient.getCpuMetricsAsync() {
            return metrics
        }

        // XPC failed, try fallback
        if enableFallbackOnFailure {
            activateFallback()
            return getFallbackCpuMetrics()
        }

        return nil
    }

    /// Get disk metrics from either XPC or fallback
    public func getDiskMetrics() async -> DiskMetricsData? {
        if forceUseFallback {
            activateFallback()
            return getFallbackDiskMetrics()
        }

        if isUsingFallback && !shouldRetryXPC() {
            return getFallbackDiskMetrics()
        }

        // Try XPC first
        if let metrics = await xpcClient.getDiskMetricsAsync() {
            return metrics
        }

        // XPC failed, try fallback
        if enableFallbackOnFailure {
            activateFallback()
            return getFallbackDiskMetrics()
        }

        return nil
    }

    /// Get temperature from either XPC or fallback
    public func getTemperature() async -> TemperatureData? {
        if forceUseFallback {
            activateFallback()
            return getFallbackTemperature()
        }

        if isUsingFallback && !shouldRetryXPC() {
            return getFallbackTemperature()
        }

        // Try XPC first
        if let temp = await xpcClient.getTemperatureAsync() {
            return temp
        }

        // XPC failed, try fallback
        if enableFallbackOnFailure {
            activateFallback()
            return getFallbackTemperature()
        }

        return nil
    }

    /// Check if XPC service is available
    public func pingXPC() async -> Bool {
        return await xpcClient.pingAsync()
    }

    // MARK: - Private Methods

    private func activateFallback() {
        lock.lock()
        guard !_isUsingFallback else {
            lock.unlock()
            return
        }

        _isUsingFallback = true

        if !fallbackInitialized {
            fallbackProvider.initialize()
            fallbackInitialized = true
        }
        lock.unlock()

        onFallbackActivated?()

        // Schedule XPC retry if enabled
        if retryXPCAfterFallback {
            scheduleXPCRetry()
        }
    }

    private func getFallbackCpuMetrics() -> CpuMetricsData? {
        ensureFallbackInitialized()
        fallbackProvider.refresh()
        return fallbackProvider.getCpuMetrics()
    }

    private func getFallbackDiskMetrics() -> DiskMetricsData? {
        ensureFallbackInitialized()
        fallbackProvider.refresh()
        return fallbackProvider.getDiskMetrics()
    }

    private func getFallbackTemperature() -> TemperatureData? {
        ensureFallbackInitialized()
        fallbackProvider.refresh()
        return fallbackProvider.getTemperature()
    }

    private func ensureFallbackInitialized() {
        lock.lock()
        if !fallbackInitialized {
            fallbackProvider.initialize()
            fallbackInitialized = true
        }
        lock.unlock()
    }

    private func handleXPCError() {
        lock.lock()
        _isXPCConnected = false
        lock.unlock()

        if enableFallbackOnFailure {
            activateFallback()
        }
    }

    private func handleXPCDisconnected() {
        lock.lock()
        _isXPCConnected = false
        lock.unlock()

        onXPCDisconnected?()

        if enableFallbackOnFailure {
            activateFallback()
        }
    }

    private func shouldRetryXPC() -> Bool {
        // Check if retry timer has fired
        return false
    }

    private func scheduleXPCRetry() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.retryTimer?.invalidate()
            self.retryTimer = Timer.scheduledTimer(
                withTimeInterval: self.retryIntervalSeconds,
                repeats: true
            ) { [weak self] _ in
                Task {
                    await self?.retryXPCConnection()
                }
            }
        }
    }

    private func retryXPCConnection() async {
        guard isUsingFallback, !forceUseFallback else { return }

        // Try to ping XPC
        if await pingXPC() {
            lock.lock()
            _isUsingFallback = false
            _isXPCConnected = true
            lock.unlock()

            DispatchQueue.main.async { [weak self] in
                self?.retryTimer?.invalidate()
                self?.retryTimer = nil
            }

            onXPCConnected?()
        }
    }
}

// MARK: - Fallback Provider

/// Simple fallback provider that uses mock data when XPC is unavailable
/// In production, this would be replaced with RustMetricsProvider
public final class FallbackMetricsProvider: MetricsProviderProtocol {

    private var initialized = false
    private var cpuUsage: Float = 0

    public init() {}

    public func initialize() {
        initialized = true
    }

    public func refresh() {
        // Simulate some CPU activity
        cpuUsage = Float.random(in: 5.0...15.0)
    }

    public func getCpuMetrics() -> CpuMetricsData? {
        guard initialized else { return nil }
        return CpuMetricsData(
            totalUsage: cpuUsage,
            coreCount: ProcessInfo.processInfo.processorCount,
            loadAverage1: 1.0,
            loadAverage5: 0.8,
            loadAverage15: 0.6,
            frequencyMHz: 0
        )
    }

    public func getDiskMetrics() -> DiskMetricsData? {
        guard initialized else { return nil }

        // Get actual disk info if possible
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )
            let total = attrs[.systemSize] as? UInt64 ?? 0
            let free = attrs[.systemFreeSize] as? UInt64 ?? 0
            let used = total > free ? total - free : 0
            let percent = total > 0 ? Float(used) / Float(total) * 100 : 0

            return DiskMetricsData(
                mountPoint: "/",
                name: "System",
                totalBytes: total,
                availableBytes: free,
                usedBytes: used,
                usagePercent: percent
            )
        } catch {
            return nil
        }
    }

    public func getTemperature() -> TemperatureData? {
        guard initialized else { return nil }
        return TemperatureData.simulated(fromCpuUsage: cpuUsage)
    }

    public func cleanup() {
        initialized = false
    }
}
