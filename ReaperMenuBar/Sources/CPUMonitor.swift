import Foundation

// Minimal FFI bindings - only what we need for CPU percentage
@_silgen_name("monitor_init")
func monitor_init()

@_silgen_name("get_cpu_usage_only")
func get_cpu_usage_only() -> Float

@_silgen_name("monitor_cleanup")
func monitor_cleanup()

class CPUMonitor {
    private var isInitialized = false
    private let initLock = NSLock()
    
    // Cache for reducing FFI calls
    private var lastCPUValue: Float = 0.0
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