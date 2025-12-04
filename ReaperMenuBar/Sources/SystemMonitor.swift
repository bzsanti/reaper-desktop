import Foundation
import ReaperShared

// FFI bindings for CPU and Disk monitoring (used as direct fallback)
@_silgen_name("monitor_init")
func monitor_init()

@_silgen_name("disk_monitor_init")
func disk_monitor_init()

@_silgen_name("get_cpu_usage_only")
func get_cpu_usage_only() -> Float

@_silgen_name("disk_monitor_refresh")
func disk_monitor_refresh()

@_silgen_name("get_primary_disk")
func get_primary_disk() -> UnsafeMutableRawPointer?

@_silgen_name("free_disk_info")
func free_disk_info(_ info: UnsafeMutableRawPointer?)

@_silgen_name("monitor_cleanup")
func monitor_cleanup()

@_silgen_name("get_cpu_metrics")
func get_cpu_metrics() -> UnsafeMutableRawPointer?

@_silgen_name("free_cpu_metrics")
func free_cpu_metrics(_ metrics: UnsafeMutableRawPointer?)

@_silgen_name("monitor_refresh")
func monitor_refresh()

// CPU Metrics struct matching Rust
struct CCpuMetrics {
    var total_usage: Float
    var core_count: Int
    var load_avg_1: Double
    var load_avg_5: Double
    var load_avg_15: Double
    var frequency_mhz: UInt64
}

// C struct matching Rust CDiskInfo
struct CDiskInfo {
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

struct DiskMetrics {
    let mountPoint: String
    let name: String
    let totalBytes: UInt64
    let availableBytes: UInt64
    let usedBytes: UInt64
    let usagePercent: Float
    
    var availableGB: Double {
        Double(availableBytes) / 1024.0 / 1024.0 / 1024.0
    }
    
    var formattedAvailable: String {
        formatBytes(availableBytes)
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024.0 && unitIndex < units.count - 1 {
            size /= 1024.0
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        } else {
            return String(format: "%.1f %@", size, units[unitIndex])
        }
    }
}

// MARK: - Safe FFI Utilities

/// Safely converts a C string pointer to Swift String
/// Returns empty string for nil pointers instead of crashing
private func safeStringFromCChar(_ cString: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr = cString else { return "" }
    return String(cString: ptr)
}

/// FFI-based MetricsProvider for direct Rust access
/// Used as fallback when XPC is unavailable
final class FFIMetricsProvider: MetricsProviderProtocol {
    private var initialized = false
    private let initLock = NSLock()

    func initialize() {
        initLock.lock()
        defer { initLock.unlock() }
        guard !initialized else { return }
        monitor_init()
        disk_monitor_init()
        initialized = true
    }

    func refresh() {
        guard initialized else { return }
        monitor_refresh()
        disk_monitor_refresh()
    }

    func getCpuMetrics() -> CpuMetricsData? {
        guard initialized else { return nil }
        guard let metricsPtr = get_cpu_metrics() else { return nil }
        defer { free_cpu_metrics(metricsPtr) }

        let cMetrics = metricsPtr.assumingMemoryBound(to: CCpuMetrics.self).pointee
        return CpuMetricsData(
            totalUsage: cMetrics.total_usage,
            coreCount: cMetrics.core_count,
            loadAverage1: cMetrics.load_avg_1,
            loadAverage5: cMetrics.load_avg_5,
            loadAverage15: cMetrics.load_avg_15,
            frequencyMHz: cMetrics.frequency_mhz
        )
    }

    func getDiskMetrics() -> DiskMetricsData? {
        guard initialized else { return nil }
        guard let diskPtr = get_primary_disk() else { return nil }
        defer { free_disk_info(diskPtr) }

        let cDisk = diskPtr.assumingMemoryBound(to: CDiskInfo.self).pointee
        let mountPoint = safeStringFromCChar(cDisk.mount_point)
        let name = safeStringFromCChar(cDisk.name)

        return DiskMetricsData(
            mountPoint: mountPoint.isEmpty ? "/" : mountPoint,
            name: name.isEmpty ? "Disk" : name,
            totalBytes: cDisk.total_bytes,
            availableBytes: cDisk.available_bytes,
            usedBytes: cDisk.used_bytes,
            usagePercent: cDisk.usage_percent
        )
    }

    func getTemperature() -> TemperatureData? {
        guard initialized else { return nil }
        let cpuUsage = get_cpu_usage_only()
        return TemperatureData.simulated(fromCpuUsage: cpuUsage)
    }

    func cleanup() {
        initLock.lock()
        defer { initLock.unlock() }
        guard initialized else { return }
        monitor_cleanup()
        initialized = false
    }
}

class SystemMonitor {
    /// MetricsManager handles XPC with FFI fallback
    private let metricsManager: MetricsManager

    // Cache for UI updates
    private var lastCPUValue: Float = 0.0
    private var lastCPUUpdateTime: Date = Date()
    private var lastDiskMetrics: DiskMetrics?
    private var lastDiskUpdateTime: Date = Date()
    private var lastTemperature: Float = 0.0
    private var lastTemperatureUpdateTime: Date = Date()
    private let cacheInterval: TimeInterval = 0.5

    init() {
        // Use FFI provider as fallback for direct Rust access
        let ffiProvider = FFIMetricsProvider()
        self.metricsManager = MetricsManager(fallbackProvider: ffiProvider)
        metricsManager.enableFallbackOnFailure = true
        metricsManager.start()
    }

    /// Get current CPU usage asynchronously
    /// Uses cached value if recent enough to reduce XPC calls
    func getCurrentCPUUsage() async -> Float {
        // Use cached value if recent enough
        if Date().timeIntervalSince(lastCPUUpdateTime) < cacheInterval {
            return lastCPUValue
        }

        // Get from MetricsManager via async XPC
        if let metrics = await metricsManager.getCpuMetrics() {
            lastCPUValue = metrics.totalUsage
            lastCPUUpdateTime = Date()
        }

        return lastCPUValue
    }

    /// Get disk metrics asynchronously
    /// Uses cached value if recent enough to reduce XPC calls
    func getDiskMetrics() async -> DiskMetrics? {
        // Use cached value if recent enough
        if let cached = lastDiskMetrics,
           Date().timeIntervalSince(lastDiskUpdateTime) < cacheInterval {
            return cached
        }

        // Get from MetricsManager via async XPC
        if let metrics = await metricsManager.getDiskMetrics() {
            let diskMetrics = DiskMetrics(
                mountPoint: metrics.mountPoint,
                name: metrics.name,
                totalBytes: metrics.totalBytes,
                availableBytes: metrics.availableBytes,
                usedBytes: metrics.usedBytes,
                usagePercent: metrics.usagePercent
            )
            lastDiskMetrics = diskMetrics
            lastDiskUpdateTime = Date()
            return diskMetrics
        }

        return lastDiskMetrics
    }

    /// Get current CPU temperature asynchronously
    /// Uses cached value if recent enough to reduce XPC calls
    func getCurrentTemperature() async -> Float {
        // Use cached value if recent enough
        if Date().timeIntervalSince(lastTemperatureUpdateTime) < cacheInterval {
            return lastTemperature
        }

        // Get from MetricsManager via async XPC
        if let temp = await metricsManager.getTemperature() {
            lastTemperature = temp.cpuTemperature
            lastTemperatureUpdateTime = Date()
        }

        return lastTemperature
    }

    /// Synchronous CPU usage for backward compatibility (uses last cached value)
    /// Prefer async version when possible
    func getCachedCPUUsage() -> Float {
        return lastCPUValue
    }

    /// Synchronous disk metrics for backward compatibility (uses last cached value)
    /// Prefer async version when possible
    func getCachedDiskMetrics() -> DiskMetrics? {
        return lastDiskMetrics
    }

    /// Synchronous temperature for backward compatibility (uses last cached value)
    /// Prefer async version when possible
    func getCachedTemperature() -> Float {
        return lastTemperature
    }

    /// Check if using XPC or fallback
    var isUsingXPC: Bool {
        return metricsManager.isXPCConnected && !metricsManager.isUsingFallback
    }

    func cleanup() {
        metricsManager.cleanup()
    }

    deinit {
        cleanup()
    }
}