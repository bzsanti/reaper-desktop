import Foundation

// MARK: - FFI Declarations

// CPU Monitor FFI
@_silgen_name("monitor_init")
private func monitor_init()

@_silgen_name("monitor_refresh")
private func monitor_refresh()

@_silgen_name("get_cpu_metrics")
private func get_cpu_metrics() -> UnsafeMutablePointer<CCpuMetricsFFI>?

@_silgen_name("free_cpu_metrics")
private func free_cpu_metrics(_ metrics: UnsafeMutablePointer<CCpuMetricsFFI>?)

@_silgen_name("get_cpu_usage_only")
private func get_cpu_usage_only() -> Float

// Disk Monitor FFI
@_silgen_name("disk_monitor_init")
private func disk_monitor_init()

@_silgen_name("disk_monitor_refresh")
private func disk_monitor_refresh()

@_silgen_name("get_primary_disk")
private func get_primary_disk() -> UnsafeMutablePointer<CDiskInfoFFI>?

@_silgen_name("free_disk_info")
private func free_disk_info(_ info: UnsafeMutablePointer<CDiskInfoFFI>?)

// MARK: - C Struct Definitions

/// C struct for CPU metrics from Rust FFI
struct CCpuMetricsFFI {
    var total_usage: Float
    var core_count: Int
    var load_avg_1: Double
    var load_avg_5: Double
    var load_avg_15: Double
    var frequency_mhz: UInt64
}

/// C struct for disk info from Rust FFI
struct CDiskInfoFFI {
    var mount_point: UnsafeMutablePointer<CChar>?
    var name: UnsafeMutablePointer<CChar>?
    var file_system: UnsafeMutablePointer<CChar>?
    var total_bytes: UInt64
    var available_bytes: UInt64
    var used_bytes: UInt64
    var usage_percent: Float
    var is_removable: UInt8
    var disk_type: UnsafeMutablePointer<CChar>?
}

// MARK: - RustMetricsProvider Implementation

/// MetricsProvider implementation that uses Rust FFI for real system metrics
/// This class wraps the Rust monitoring libraries and provides data to Swift
public final class RustMetricsProvider: MetricsProviderProtocol {

    // MARK: - Properties

    private let lock = NSLock()
    private var _isReady: Bool = false
    private var lastRefreshTime: Date?
    private let minimumRefreshInterval: TimeInterval = 0.5

    // Cached values
    private var cachedCpuMetrics: CpuMetricsData?
    private var cachedDiskMetrics: DiskMetricsData?
    private var cachedTemperature: TemperatureData?

    /// Whether the provider is initialized and ready
    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReady
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - MetricsProviderProtocol

    public func initialize() {
        lock.lock()
        defer { lock.unlock() }

        guard !_isReady else { return }

        // Initialize Rust monitors
        monitor_init()
        disk_monitor_init()

        // Perform initial refresh to warm up sysinfo
        // sysinfo needs multiple readings to calculate CPU deltas
        monitor_refresh()
        disk_monitor_refresh()

        _isReady = true
    }

    public func refresh() {
        lock.lock()
        defer { lock.unlock() }

        guard _isReady else { return }

        // Check minimum refresh interval
        if let lastTime = lastRefreshTime,
           Date().timeIntervalSince(lastTime) < minimumRefreshInterval {
            return
        }

        // Refresh Rust monitors
        monitor_refresh()
        disk_monitor_refresh()

        // Clear cache to force fresh reads
        cachedCpuMetrics = nil
        cachedDiskMetrics = nil
        cachedTemperature = nil

        lastRefreshTime = Date()
    }

    public func getCpuMetrics() -> CpuMetricsData? {
        lock.lock()
        defer { lock.unlock() }

        guard _isReady else { return nil }

        // Return cached value if available
        if let cached = cachedCpuMetrics {
            return cached
        }

        // Fetch from Rust
        guard let metricsPtr = get_cpu_metrics() else { return nil }
        defer { free_cpu_metrics(metricsPtr) }

        let cMetrics = metricsPtr.pointee

        let metrics = CpuMetricsData(
            totalUsage: cMetrics.total_usage,
            coreCount: cMetrics.core_count,
            loadAverage1: cMetrics.load_avg_1,
            loadAverage5: cMetrics.load_avg_5,
            loadAverage15: cMetrics.load_avg_15,
            frequencyMHz: cMetrics.frequency_mhz
        )

        cachedCpuMetrics = metrics
        return metrics
    }

    public func getDiskMetrics() -> DiskMetricsData? {
        lock.lock()
        defer { lock.unlock() }

        guard _isReady else { return nil }

        // Return cached value if available
        if let cached = cachedDiskMetrics {
            return cached
        }

        // Fetch from Rust
        guard let diskPtr = get_primary_disk() else { return nil }
        defer { free_disk_info(diskPtr) }

        let cDisk = diskPtr.pointee

        let mountPoint = safeStringFromCChar(cDisk.mount_point)
        let name = safeStringFromCChar(cDisk.name)

        let metrics = DiskMetricsData(
            mountPoint: mountPoint.isEmpty ? "/" : mountPoint,
            name: name.isEmpty ? "Disk" : name,
            totalBytes: cDisk.total_bytes,
            availableBytes: cDisk.available_bytes,
            usedBytes: cDisk.used_bytes,
            usagePercent: cDisk.usage_percent
        )

        cachedDiskMetrics = metrics
        return metrics
    }

    public func getTemperature() -> TemperatureData? {
        lock.lock()
        defer { lock.unlock() }

        guard _isReady else { return nil }

        // Return cached value if available
        if let cached = cachedTemperature {
            return cached
        }

        // Get CPU usage first (we need it for simulated temperature)
        let cpuUsage = get_cpu_usage_only()

        // On macOS, real CPU temperature requires SMC access which is not available
        // without elevated privileges. We simulate temperature based on CPU usage.
        // Formula: base temp (35C) + CPU usage factor
        let temperature = TemperatureData.simulated(fromCpuUsage: cpuUsage)

        cachedTemperature = temperature
        return temperature
    }

    public func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        cachedCpuMetrics = nil
        cachedDiskMetrics = nil
        cachedTemperature = nil
        lastRefreshTime = nil
        _isReady = false

        // Note: Rust monitors use static singletons and don't need explicit cleanup
    }

    // MARK: - Private Helpers

    /// Safely convert C string to Swift String
    private func safeStringFromCChar(_ cString: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr = cString else { return "" }
        return String(cString: ptr)
    }
}
