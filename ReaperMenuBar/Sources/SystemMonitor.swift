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
    private var lastDiskMetrics: DiskMetrics?
    private var lastUpdateTime: Date = Date()
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
        if Date().timeIntervalSince(lastUpdateTime) < cacheInterval {
            return lastCPUValue
        }
        
        // Get fresh value
        let cpuUsage = get_cpu_usage_only()
        
        // Update cache
        lastCPUValue = cpuUsage
        lastUpdateTime = Date()
        
        return cpuUsage
    }
    
    func getDiskMetrics() -> DiskMetrics? {
        // Use cached value if recent enough
        if let cached = lastDiskMetrics,
           Date().timeIntervalSince(lastUpdateTime) < cacheInterval {
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
        
        return metrics
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