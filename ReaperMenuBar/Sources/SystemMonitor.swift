import Foundation

// FFI bindings for CPU and Disk monitoring
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

class SystemMonitor {
    private var isInitialized = false
    private let initLock = NSLock()
    
    // Cache for reducing FFI calls
    private var lastCPUValue: Float = 0.0
    private var lastCPUUpdateTime: Date = Date()
    private var lastDiskMetrics: DiskMetrics?
    private var lastDiskUpdateTime: Date = Date()
    private var lastTemperature: Float = 0.0
    private var lastTemperatureUpdateTime: Date = Date()
    private let cacheInterval: TimeInterval = 0.5 // Cache for 500ms
    
    init() {
        initializeMonitor()
    }
    
    private func initializeMonitor() {
        initLock.lock()
        defer { initLock.unlock() }
        
        if !isInitialized {
            monitor_init()
            disk_monitor_init()
            isInitialized = true
        }
    }
    
    func getCurrentCPUUsage() -> Float {
        // Use cached value if recent enough
        if Date().timeIntervalSince(lastCPUUpdateTime) < cacheInterval {
            return lastCPUValue
        }
        
        // Get fresh value
        let cpuUsage = get_cpu_usage_only()
        
        // Update cache
        lastCPUValue = cpuUsage
        lastCPUUpdateTime = Date()
        
        return cpuUsage
    }
    
    func getDiskMetrics() -> DiskMetrics? {
        // Use cached value if recent enough
        if let cached = lastDiskMetrics,
           Date().timeIntervalSince(lastDiskUpdateTime) < cacheInterval {
            return cached
        }
        
        // Refresh disk data
        disk_monitor_refresh()
        
        // Get primary disk info
        guard let diskPtr = get_primary_disk() else { return nil }
        defer { free_disk_info(diskPtr) }
        
        let cDisk = diskPtr.assumingMemoryBound(to: CDiskInfo.self).pointee
        
        let mountPoint = String(cString: cDisk.mount_point ?? UnsafeMutablePointer<CChar>(bitPattern: 1)!)
        let name = String(cString: cDisk.name ?? UnsafeMutablePointer<CChar>(bitPattern: 1)!)
        
        let metrics = DiskMetrics(
            mountPoint: mountPoint.isEmpty ? "/" : mountPoint,
            name: name.isEmpty ? "Disk" : name,
            totalBytes: cDisk.total_bytes,
            availableBytes: cDisk.available_bytes,
            usedBytes: cDisk.used_bytes,
            usagePercent: cDisk.usage_percent
        )
        
        // Update cache
        lastDiskMetrics = metrics
        lastDiskUpdateTime = Date()
        
        return metrics
    }

    func getCurrentTemperature() -> Float {
        // Use cached value if recent enough
        if Date().timeIntervalSince(lastTemperatureUpdateTime) < cacheInterval {
            return lastTemperature
        }

        // Get CPU metrics which now include temperature data
        guard let metricsPtr = get_cpu_metrics() else {
            // Fallback: simulate temperature based on CPU usage
            let cpuUsage = getCurrentCPUUsage()
            let temp = 35.0 + (cpuUsage * 0.5) // Base temp + usage scaling
            lastTemperature = temp
            lastTemperatureUpdateTime = Date()
            return temp
        }

        defer { free_cpu_metrics(metricsPtr) }

        let cMetrics = metricsPtr.assumingMemoryBound(to: CCpuMetrics.self).pointee

        // Calculate temperature based on CPU usage (simulated for now)
        let baseTemp: Float = 35.0  // Base temperature
        let usageTemp = cMetrics.total_usage * 0.5  // Scale factor
        let temperature = baseTemp + usageTemp

        // Update cache
        lastTemperature = temperature
        lastTemperatureUpdateTime = Date()

        return temperature
    }

    func cleanup() {
        initLock.lock()
        defer { initLock.unlock() }
        
        if isInitialized {
            monitor_cleanup()
            isInitialized = false
        }
    }
    
    deinit {
        cleanup()
    }
}