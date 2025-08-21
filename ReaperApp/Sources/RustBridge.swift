import Foundation
import AppKit
import SwiftUI

// MARK: - Process Tree FFI Declarations
@_silgen_name("get_process_tree")
func get_process_tree() -> UnsafeMutableRawPointer?

@_silgen_name("free_process_tree")
func free_process_tree(_ tree: UnsafeMutableRawPointer?)

// C struct matching Rust CProcessTreeNode
struct CProcessTreeNode {
    var pid: UInt32
    var name: UnsafeMutablePointer<CChar>?
    var command: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var command_count: Int
    var executable_path: UnsafeMutablePointer<CChar>?
    var cpu_usage: Float
    var memory_mb: Double
    var status: UnsafeMutablePointer<CChar>?
    var thread_count: Int
    var children: UnsafeMutablePointer<CProcessTreeNode>?
    var children_count: Int
    var total_cpu_usage: Float
    var total_memory_mb: Double
    var descendant_count: Int
}

// C struct matching Rust CProcessTree
struct CProcessTree {
    var roots: UnsafeMutablePointer<CProcessTreeNode>?
    var roots_count: Int
    var total_processes: Int
}

struct ProcessInfo: Identifiable {
    let id: UInt32
    let pid: UInt32
    let name: String
    let cpuUsage: Float
    let memoryMB: Double
    let status: String
    let parentPid: UInt32
    let threadCount: Int
    let runTime: UInt64
    let userTime: Double
    let systemTime: Double
    
    // Advanced analysis fields
    let ioWaitTimeMs: UInt64
    let contextSwitches: UInt64
    let minorFaults: UInt64
    let majorFaults: UInt64
    let priority: Int32
    let isUnkillable: Bool
    let isProblematic: Bool
    
    init(pid: UInt32, name: String, cpuUsage: Float, memoryMB: Double, status: String, parentPid: UInt32, threadCount: Int, runTime: UInt64, userTime: Double = 0.0, systemTime: Double = 0.0, ioWaitTimeMs: UInt64 = 0, contextSwitches: UInt64 = 0, minorFaults: UInt64 = 0, majorFaults: UInt64 = 0, priority: Int32 = 0, isUnkillable: Bool = false, isProblematic: Bool = false) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.cpuUsage = cpuUsage
        self.memoryMB = memoryMB
        self.status = status
        self.parentPid = parentPid
        self.threadCount = threadCount
        self.runTime = runTime
        self.userTime = userTime
        self.systemTime = systemTime
        self.ioWaitTimeMs = ioWaitTimeMs
        self.contextSwitches = contextSwitches
        self.minorFaults = minorFaults
        self.majorFaults = majorFaults
        self.priority = priority
        self.isUnkillable = isUnkillable
        self.isProblematic = isProblematic
    }
}


struct CpuMetrics {
    let totalUsage: Float
    let coreCount: Int
    let loadAverage1: Double
    let loadAverage5: Double
    let loadAverage15: Double
    let frequencyMHz: UInt64
}

struct MemoryMetrics {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let freeBytes: UInt64
    let swapTotalBytes: UInt64
    let swapUsedBytes: UInt64
    let swapFreeBytes: UInt64
    let cachedBytes: UInt64
    let bufferBytes: UInt64
    let usagePercent: Float
    let swapUsagePercent: Float
    let memoryPressure: String
}

struct ProcessMemoryInfo: Identifiable {
    let id: UInt32
    let pid: UInt32
    let name: String
    let memoryBytes: UInt64
    let virtualMemoryBytes: UInt64
    let memoryPercent: Float
    let isGrowing: Bool
    let growthRateMBPerMin: Float
    
    var memoryMB: Double {
        Double(memoryBytes) / 1024.0 / 1024.0
    }
    
    var virtualMemoryMB: Double {
        Double(virtualMemoryBytes) / 1024.0 / 1024.0
    }
}

struct DiskMetrics: Identifiable {
    let id: String  // mount point as ID
    let mountPoint: String
    let name: String
    let fileSystem: String
    let totalBytes: UInt64
    let availableBytes: UInt64
    let usedBytes: UInt64
    let usagePercent: Float
    let isRemovable: Bool
    let diskType: String
    
    var totalGB: Double {
        Double(totalBytes) / 1024.0 / 1024.0 / 1024.0
    }
    
    var availableGB: Double {
        Double(availableBytes) / 1024.0 / 1024.0 / 1024.0
    }
    
    var usedGB: Double {
        Double(usedBytes) / 1024.0 / 1024.0 / 1024.0
    }
    
    func formatBytes(_ bytes: UInt64) -> String {
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

struct HardwareMetrics {
    let temperatures: [TemperatureSensor]
    let cpuFrequencyMHz: UInt64
    let thermalState: ThermalState
    let cpuPowerWatts: Float?
    let gpuPowerWatts: Float?
    let totalPowerWatts: Float?
    
    var cpuFrequencyGHz: Double {
        Double(cpuFrequencyMHz) / 1000.0
    }
}

struct TemperatureSensor: Identifiable {
    let id = UUID()
    let name: String
    let valueCelsius: Float
    let sensorType: SensorType
    let isCritical: Bool
    
    var valueFahrenheit: Float {
        valueCelsius * 9.0 / 5.0 + 32.0
    }
}

enum SensorType: UInt8 {
    case cpuCore = 0
    case cpuPackage = 1
    case gpu = 2
    case memory = 3
    case storage = 4
    case battery = 5
    case other = 6
    
    var icon: String {
        switch self {
        case .cpuCore, .cpuPackage: return "cpu"
        case .gpu: return "gpu.card"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.100"
        case .other: return "thermometer"
        }
    }
    
    var displayName: String {
        switch self {
        case .cpuCore: return "CPU Core"
        case .cpuPackage: return "CPU Package"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .storage: return "Storage"
        case .battery: return "Battery"
        case .other: return "Other"
        }
    }
}

enum ThermalState: UInt8 {
    case normal = 0
    case warm = 1
    case hot = 2
    case throttling = 3
    
    var color: Color {
        switch self {
        case .normal: return .green
        case .warm: return .yellow
        case .hot: return .orange
        case .throttling: return .red
        }
    }
    
    var description: String {
        switch self {
        case .normal: return "Normal"
        case .warm: return "Warm"
        case .hot: return "Hot"
        case .throttling: return "Throttling"
        }
    }
}

// Network monitoring structures
struct NetworkConnection: Identifiable {
    let id: String
    let pid: Int32?
    let processName: String
    let localAddress: String
    let localPort: UInt16
    let remoteAddress: String
    let remotePort: UInt16
    let networkProtocol: String
    let state: String
    let bytesSent: UInt64
    let bytesReceived: UInt64
    
    var stateColor: Color {
        switch state.lowercased() {
        case "established": return .green
        case "listen": return .blue
        case "syn sent", "syn received": return .yellow
        case "time wait", "close wait": return .orange
        case "closed", "last ack", "fin wait 1", "fin wait 2": return .gray
        default: return .secondary
        }
    }
}

struct BandwidthStats {
    let currentUploadBps: UInt64
    let currentDownloadBps: UInt64
    let peakUploadBps: UInt64
    let peakDownloadBps: UInt64
    let averageUploadBps: UInt64
    let averageDownloadBps: UInt64
    
    var currentUploadMbps: Double {
        Double(currentUploadBps) / (1024 * 1024)
    }
    
    var currentDownloadMbps: Double {
        Double(currentDownloadBps) / (1024 * 1024)
    }
}

struct NetworkMetrics {
    let connections: [NetworkConnection]
    let bandwidth: BandwidthStats
    let totalBytesSent: UInt64
    let totalBytesReceived: UInt64
    let packetsSent: UInt64
    let packetsReceived: UInt64
    let activeInterfaces: [String]
    
    var totalBytesSentGB: Double {
        Double(totalBytesSent) / (1024 * 1024 * 1024)
    }
    
    var totalBytesReceivedGB: Double {
        Double(totalBytesReceived) / (1024 * 1024 * 1024)
    }
}

@_silgen_name("monitor_init")
func monitor_init()

@_silgen_name("monitor_refresh")
func monitor_refresh()

@_silgen_name("get_all_processes")
func get_all_processes() -> UnsafeMutablePointer<CProcessList>?

// CPU Limiting functions
@_silgen_name("limit_process_cpu")
func limit_process_cpu(_ pid: UInt32, _ maxPercent: Float) -> Int32

@_silgen_name("remove_process_limit")
func remove_process_limit(_ pid: UInt32) -> Int32

@_silgen_name("set_process_nice")
func set_process_nice(_ pid: UInt32, _ niceValue: Int32) -> Int32

@_silgen_name("get_all_cpu_limits")
func get_all_cpu_limits() -> UnsafeMutablePointer<CCpuLimitList>?

@_silgen_name("free_cpu_limits")
func free_cpu_limits(_ list: UnsafeMutablePointer<CCpuLimitList>?)

@_silgen_name("has_process_limit")
func has_process_limit(_ pid: UInt32) -> UInt8

@_silgen_name("get_high_cpu_processes")
func get_high_cpu_processes(_ threshold: Float) -> UnsafeMutablePointer<CProcessList>?

@_silgen_name("get_cpu_metrics")
func get_cpu_metrics() -> UnsafeMutablePointer<CCpuMetrics>?

@_silgen_name("free_process_list")
func free_process_list(_ list: UnsafeMutablePointer<CProcessList>?)

@_silgen_name("free_cpu_metrics")
func free_cpu_metrics(_ metrics: UnsafeMutablePointer<CCpuMetrics>?)

@_silgen_name("terminate_process")
func terminate_process(_ pid: UInt32) -> UnsafeMutablePointer<CActionResponse>?

@_silgen_name("force_kill_process")
func force_kill_process(_ pid: UInt32) -> UnsafeMutablePointer<CActionResponse>?

@_silgen_name("suspend_process")
func suspend_process(_ pid: UInt32) -> UnsafeMutablePointer<CActionResponse>?

@_silgen_name("resume_process")
func resume_process(_ pid: UInt32) -> UnsafeMutablePointer<CActionResponse>?

@_silgen_name("free_action_response")
func free_action_response(_ response: UnsafeMutablePointer<CActionResponse>?)

@_silgen_name("get_process_details")
func get_process_details(_ pid: UInt32) -> UnsafeMutablePointer<CProcessDetails>?

@_silgen_name("free_process_details")
func free_process_details(_ details: UnsafeMutablePointer<CProcessDetails>?)

// Hardware monitor FFI functions
@_silgen_name("hardware_monitor_init")
func hardware_monitor_init()

@_silgen_name("hardware_monitor_refresh")
func hardware_monitor_refresh()

@_silgen_name("get_hardware_metrics")
func get_hardware_metrics() -> UnsafeMutablePointer<CHardwareMetrics>?

@_silgen_name("free_hardware_metrics")
func free_hardware_metrics(_ metrics: UnsafeMutablePointer<CHardwareMetrics>?)

@_silgen_name("get_thermal_state")
func get_thermal_state() -> UInt8

// Network monitor FFI functions
@_silgen_name("network_monitor_init")
func network_monitor_init()

@_silgen_name("get_network_metrics")
func get_network_metrics() -> UnsafeMutablePointer<CNetworkMetrics>?

@_silgen_name("free_network_metrics")
func free_network_metrics(_ metrics: UnsafeMutablePointer<CNetworkMetrics>?)

@_silgen_name("get_process_connections")
func get_process_connections(_ pid: UInt32) -> UnsafeMutablePointer<CNetworkConnectionList>?

@_silgen_name("free_connection_list")
func free_connection_list(_ list: UnsafeMutablePointer<CNetworkConnectionList>?)

@_silgen_name("get_process_bandwidth")
func get_process_bandwidth(_ pid: UInt32) -> CBandwidthStats

@_silgen_name("refresh_network_data")
func refresh_network_data()

// Disk monitor FFI functions
@_silgen_name("disk_monitor_init")
func disk_monitor_init()

@_silgen_name("disk_monitor_refresh")
func disk_monitor_refresh()

@_silgen_name("get_primary_disk")
func get_primary_disk() -> UnsafeMutablePointer<CDiskInfo>?

@_silgen_name("get_all_disks")
func get_all_disks() -> UnsafeMutablePointer<CDiskList>?

@_silgen_name("free_disk_info")
func free_disk_info(_ info: UnsafeMutablePointer<CDiskInfo>?)

@_silgen_name("free_disk_list")
func free_disk_list(_ list: UnsafeMutablePointer<CDiskList>?)

// Memory monitor FFI functions
@_silgen_name("memory_monitor_init")
func memory_monitor_init()

@_silgen_name("memory_monitor_refresh")
func memory_monitor_refresh()

@_silgen_name("get_memory_info")
func get_memory_info() -> UnsafeMutablePointer<CMemoryInfo>?

@_silgen_name("free_memory_info")
func free_memory_info(_ info: UnsafeMutablePointer<CMemoryInfo>?)

@_silgen_name("get_process_memory_list")
func get_process_memory_list() -> UnsafeMutablePointer<CProcessMemoryList>?

@_silgen_name("get_top_memory_processes")
func get_top_memory_processes(_ limit: Int) -> UnsafeMutablePointer<CProcessMemoryList>?

@_silgen_name("detect_memory_leaks")
func detect_memory_leaks() -> UnsafeMutablePointer<CProcessMemoryList>?

@_silgen_name("free_process_memory_list")
func free_process_memory_list(_ list: UnsafeMutablePointer<CProcessMemoryList>?)

@_silgen_name("get_memory_pressure")
func get_memory_pressure() -> UnsafeMutablePointer<CChar>?

@_silgen_name("free_string")
func free_string(_ s: UnsafeMutablePointer<CChar>?)

enum CActionResult: Int32 {
    case success = 0
    case processNotFound = 1
    case permissionDenied = 2
    case processUnkillable = 3
    case alreadyInState = 4
    case unknownError = 5
}

struct CActionResponse {
    var result: CActionResult
    var message: UnsafeMutablePointer<CChar>?
}

struct CEnvironmentVar {
    var key: UnsafeMutablePointer<CChar>?
    var value: UnsafeMutablePointer<CChar>?
}

struct CProcessInfo {
    var pid: UInt32
    var name: UnsafeMutablePointer<CChar>?
    var cpu_usage: Float
    var memory_mb: Double
    var status: UnsafeMutablePointer<CChar>?
    var parent_pid: UInt32
    var thread_count: Int
    var run_time: UInt64
    var user_time: Double
    var system_time: Double
    var io_wait_time_ms: UInt64
    var context_switches: UInt64
    var minor_faults: UInt64
    var major_faults: UInt64
    var priority: Int32
    var is_unkillable: UInt8
    var is_problematic: UInt8
}

struct CProcessList {
    var processes: UnsafeMutablePointer<CProcessInfo>?
    var count: Int
}

struct CCpuMetrics {
    var total_usage: Float
    var core_count: Int
    var load_avg_1: Double
    var load_avg_5: Double
    var load_avg_15: Double
    var frequency_mhz: UInt64
}

struct CProcessDetails {
    var pid: UInt32
    var name: UnsafeMutablePointer<CChar>?
    var exe_path: UnsafeMutablePointer<CChar>?
    var command_line: UnsafeMutablePointer<CChar>?
    var working_directory: UnsafeMutablePointer<CChar>?
    var user_id: UInt32
    var parent_pid: UInt32
    var threads_count: Int
    var open_files_count: Int
    var cpu_usage: Float
    var memory_usage: UInt64
    var virtual_memory: UInt64
    var start_time: UInt64
    var state: UnsafeMutablePointer<CChar>?
    var environment_count: Int
    var environment_vars: UnsafeMutablePointer<CEnvironmentVar>?
}

struct CMemoryInfo {
    var total_bytes: UInt64
    var used_bytes: UInt64
    var available_bytes: UInt64
    var free_bytes: UInt64
    var swap_total_bytes: UInt64
    var swap_used_bytes: UInt64
    var swap_free_bytes: UInt64
    var cached_bytes: UInt64
    var buffer_bytes: UInt64
    var usage_percent: Float
    var swap_usage_percent: Float
    var memory_pressure: UnsafeMutablePointer<CChar>?
}

struct CProcessMemoryInfo {
    var pid: UInt32
    var name: UnsafeMutablePointer<CChar>?
    var memory_bytes: UInt64
    var virtual_memory_bytes: UInt64
    var memory_percent: Float
    var is_growing: UInt8
    var growth_rate_mb_per_min: Float
}

struct CProcessMemoryList {
    var processes: UnsafeMutablePointer<CProcessMemoryInfo>?
    var count: Int
}

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

struct CDiskList {
    var disks: UnsafeMutablePointer<CDiskInfo>?
    var count: Int
}

struct CHardwareMetrics {
    var temperatures: UnsafeMutablePointer<CTemperatureSensor>?
    var temperature_count: Int
    var cpu_frequency_mhz: UInt64
    var thermal_state: UInt8
    var cpu_power_watts: Float
    var gpu_power_watts: Float
    var total_power_watts: Float
    var has_power_metrics: UInt8
}

struct CTemperatureSensor {
    var name: UnsafeMutablePointer<CChar>?
    var value_celsius: Float
    var sensor_type: UInt8
    var is_critical: UInt8
}

// Network monitor structures
struct CNetworkConnection {
    var pid: Int32 // -1 for None
    var process_name: UnsafeMutablePointer<CChar>?
    var local_address: UnsafeMutablePointer<CChar>?
    var local_port: UInt16
    var remote_address: UnsafeMutablePointer<CChar>?
    var remote_port: UInt16
    var network_protocol: UnsafeMutablePointer<CChar>?
    var state: UnsafeMutablePointer<CChar>?
    var bytes_sent: UInt64
    var bytes_received: UInt64
}

struct CNetworkConnectionList {
    var connections: UnsafeMutablePointer<CNetworkConnection>?
    var count: Int
}

struct CBandwidthStats {
    var current_upload_bps: UInt64
    var current_download_bps: UInt64
    var peak_upload_bps: UInt64
    var peak_download_bps: UInt64
    var average_upload_bps: UInt64
    var average_download_bps: UInt64
}

struct CNetworkMetrics {
    var connections: CNetworkConnectionList
    var bandwidth: CBandwidthStats
    var total_bytes_sent: UInt64
    var total_bytes_received: UInt64
    var packets_sent: UInt64
    var packets_received: UInt64
    var active_interfaces: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var interface_count: Int
}

// CPU Limit structures
struct CCpuLimit {
    var pid: UInt32
    var max_cpu_percent: Float
    var nice_value: Int32
    var limit_type: UInt8  // 0=Nice, 1=Affinity, 2=CpuLimit, 3=Combined
}

struct CCpuLimitList {
    var limits: UnsafeMutablePointer<CCpuLimit>?
    var count: Int
}

struct CpuLimitInfo: Identifiable {
    let id: UInt32
    let pid: UInt32
    let maxCpuPercent: Float
    let niceValue: Int32
    let limitType: CpuLimitType
    var processName: String? = nil  // Will be populated by matching with processes
    
    enum CpuLimitType {
        case nice
        case affinity
        case cpuLimit
        case combined
        
        init(rawValue: UInt8) {
            switch rawValue {
            case 1: self = .affinity
            case 2: self = .cpuLimit
            case 3: self = .combined
            default: self = .nice
            }
        }
        
        var description: String {
            switch self {
            case .nice: return "Nice"
            case .affinity: return "CPU Affinity"
            case .cpuLimit: return "cpulimit"
            case .combined: return "Combined"
            }
        }
    }
}

struct ProcessDetailsInfo {
    let pid: UInt32
    let executablePath: String
    let arguments: [String]
    let openFiles: [String]
    let connections: [String]
    let user: String
    let group: String
}

enum CPULimitPreset: CaseIterable {
    case high       // 75%
    case medium     // 50%
    case low        // 25%
    case minimal    // 10%
    
    var percentage: Float {
        switch self {
        case .high: return 75.0
        case .medium: return 50.0
        case .low: return 25.0
        case .minimal: return 10.0
        }
    }
    
    var description: String {
        switch self {
        case .high: return "75% CPU"
        case .medium: return "50% CPU"
        case .low: return "25% CPU"
        case .minimal: return "10% CPU"
        }
    }
}

@MainActor
class RustBridge: ObservableObject {
    @Published var processes: [ProcessInfo] = []
    @Published var cpuMetrics: CpuMetrics?
    @Published var highCpuProcesses: [ProcessInfo] = []
    @Published var memoryMetrics: MemoryMetrics?
    @Published var topMemoryProcesses: [ProcessMemoryInfo] = []
    @Published var memoryLeaks: [ProcessMemoryInfo] = []
    @Published var cpuLimitedProcesses: [CpuLimitInfo] = []  // Track CPU-limited processes
    @Published var limitedProcessPids: Set<UInt32> = []  // Quick lookup for limited PIDs
    @Published var hardwareMetrics: HardwareMetrics?
    @Published var networkMetrics: NetworkMetrics?
    @Published var primaryDisk: DiskMetrics?
    @Published var allDisks: [DiskMetrics] = []
    
    private var refreshTimer: Timer?
    private let updateQueue = DispatchQueue(label: "com.cpumonitor.update", qos: .userInitiated)
    private var isUpdating = false
    
    // Adaptive refresh intervals
    private var currentRefreshInterval: TimeInterval = 2.0
    private let activeRefreshInterval: TimeInterval = 1.0
    private let backgroundRefreshInterval: TimeInterval = 5.0
    private let idleRefreshInterval: TimeInterval = 10.0
    
    // Track app state
    private var isAppActive = true
    private var lastSignificantChange = Date()
    private var previousCpuUsage: Float = 0
    
    init() {
        monitor_init()
        memory_monitor_init()
        hardware_monitor_init()
        network_monitor_init()
        disk_monitor_init()
        setupAppStateObservers()
        startRefreshTimer()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        
        // Window visibility observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillMiniaturize),
            name: NSWindow.willMiniaturizeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidDeminiaturize),
            name: NSWindow.didDeminiaturizeNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        isAppActive = true
        currentRefreshInterval = activeRefreshInterval
        restartTimer()
        refresh() // Immediate refresh when becoming active
    }
    
    @objc private func appDidResignActive() {
        isAppActive = false
        currentRefreshInterval = backgroundRefreshInterval
        restartTimer()
    }
    
    @objc private func appWillTerminate() {
        Task { @MainActor in
            refreshTimer?.invalidate()
        }
    }
    
    @objc private func windowDidBecomeKey() {
        // Window became active, resume normal refresh
        if isAppActive {
            currentRefreshInterval = activeRefreshInterval
            restartTimer()
            refresh()
        }
    }
    
    @objc private func windowDidResignKey() {
        // Window lost focus, slow down
        currentRefreshInterval = backgroundRefreshInterval
        restartTimer()
    }
    
    @objc private func windowWillMiniaturize() {
        // Window is being minimized, stop refreshing
        refreshTimer?.invalidate()
    }
    
    @objc private func windowDidDeminiaturize() {
        // Window was restored, resume refreshing
        if isAppActive {
            currentRefreshInterval = activeRefreshInterval
            startRefreshTimer()
            refresh()
        }
    }
    
    private func restartTimer() {
        refreshTimer?.invalidate()
        startRefreshTimer()
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: currentRefreshInterval, repeats: true) { _ in
            Task { @MainActor in
                self.refresh()
            }
        }
    }
    
    private func adjustRefreshRate() {
        // Check if there's significant CPU change
        if let metrics = cpuMetrics {
            let cpuDelta = abs(metrics.totalUsage - previousCpuUsage)
            
            if cpuDelta > 5.0 {
                // Significant change detected
                lastSignificantChange = Date()
                if isAppActive {
                    currentRefreshInterval = activeRefreshInterval
                }
            } else if Date().timeIntervalSince(lastSignificantChange) > 30 {
                // No significant changes for 30 seconds, slow down
                if isAppActive {
                    currentRefreshInterval = min(currentRefreshInterval * 1.5, idleRefreshInterval)
                }
            }
            
            previousCpuUsage = metrics.totalUsage
            
            // Restart timer if interval changed significantly
            if abs(refreshTimer?.timeInterval ?? 0 - currentRefreshInterval) > 0.5 {
                restartTimer()
            }
        }
    }
    
    func refresh() {
        // Skip refresh completely if app is not active
        guard isAppActive else { return }
        guard !isUpdating else { return }
        
        isUpdating = true
        
        Task {
            await withCheckedContinuation { continuation in
                updateQueue.async { [weak self] in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    monitor_refresh()
                    memory_monitor_refresh()
                    hardware_monitor_refresh()
                    refresh_network_data()
                    disk_monitor_refresh()
                    
                    let newProcesses = self.fetchProcessesSync()
                    let newMetrics = self.fetchCpuMetricsSync()
                    let newHighCpuProcesses = self.fetchHighCpuProcessesSync()
                    let newMemoryMetrics = self.fetchMemoryMetricsSync()
                    let newTopMemoryProcesses = self.fetchTopMemoryProcessesSync()
                    let newMemoryLeaks = self.detectMemoryLeaksSync()
                    let newCpuLimits = self.fetchCpuLimitsSync()
                    let newHardwareMetrics = self.fetchHardwareMetricsSync()
                    let newNetworkMetrics = self.fetchNetworkMetricsSync()
                    let newPrimaryDisk = self.fetchPrimaryDiskSync()
                    let newAllDisks = self.fetchAllDisksSync()
                    
                    Task { @MainActor in
                        self.processes = newProcesses
                        self.cpuMetrics = newMetrics
                        self.highCpuProcesses = newHighCpuProcesses
                        self.memoryMetrics = newMemoryMetrics
                        self.topMemoryProcesses = newTopMemoryProcesses
                        self.memoryLeaks = newMemoryLeaks
                        self.cpuLimitedProcesses = newCpuLimits
                        self.limitedProcessPids = Set(newCpuLimits.map { $0.pid })
                        self.hardwareMetrics = newHardwareMetrics
                        self.networkMetrics = newNetworkMetrics
                        self.primaryDisk = newPrimaryDisk
                        self.allDisks = newAllDisks
                        
                        // Adjust refresh rate based on activity
                        self.adjustRefreshRate()
                        self.isUpdating = false
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    // Helper function for safe C string conversion
    nonisolated private func safeStringFromCString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr = ptr else { return "Unknown" }
        // Extra check to ensure pointer is not null
        guard Int(bitPattern: ptr) != 0 else { return "Unknown" }
        return String(cString: ptr)
    }
    
    nonisolated private func fetchProcessesSync() -> [ProcessInfo] {
        guard let listPtr = get_all_processes() else { return [] }
        defer { free_process_list(listPtr) }
        
        let list = listPtr.pointee
        guard let processesPtr = list.processes else { return [] }
        
        var newProcesses: [ProcessInfo] = []
        
        for i in 0..<list.count {
            let cProcess = processesPtr[i]
            
            // Use safe conversion helper
            let name = safeStringFromCString(cProcess.name)
            let status = safeStringFromCString(cProcess.status)
            
            let process = ProcessInfo(
                pid: cProcess.pid,
                name: name,
                cpuUsage: cProcess.cpu_usage,
                memoryMB: cProcess.memory_mb,
                status: status,
                parentPid: cProcess.parent_pid,
                threadCount: cProcess.thread_count,
                runTime: cProcess.run_time,
                userTime: cProcess.user_time,
                systemTime: cProcess.system_time,
                ioWaitTimeMs: cProcess.io_wait_time_ms,
                contextSwitches: cProcess.context_switches,
                minorFaults: cProcess.minor_faults,
                majorFaults: cProcess.major_faults,
                priority: cProcess.priority,
                isUnkillable: cProcess.is_unkillable != 0,
                isProblematic: cProcess.is_problematic != 0
            )
            newProcesses.append(process)
        }
        
        return newProcesses.sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    nonisolated private func fetchCpuMetricsSync() -> CpuMetrics? {
        guard let metricsPtr = get_cpu_metrics() else { return nil }
        defer { free_cpu_metrics(metricsPtr) }
        
        let cMetrics = metricsPtr.pointee
        let metrics = CpuMetrics(
            totalUsage: cMetrics.total_usage,
            coreCount: cMetrics.core_count,
            loadAverage1: cMetrics.load_avg_1,
            loadAverage5: cMetrics.load_avg_5,
            loadAverage15: cMetrics.load_avg_15,
            frequencyMHz: cMetrics.frequency_mhz
        )
        
        return metrics
    }
    
    nonisolated private func fetchHighCpuProcessesSync() -> [ProcessInfo] {
        guard let listPtr = get_high_cpu_processes(25.0) else { return [] }
        defer { free_process_list(listPtr) }
        
        let list = listPtr.pointee
        guard let processesPtr = list.processes else { return [] }
        
        var highCpuProcs: [ProcessInfo] = []
        
        for i in 0..<list.count {
            let cProcess = processesPtr[i]
            
            // Use safe conversion helper
            let name = safeStringFromCString(cProcess.name)
            let status = safeStringFromCString(cProcess.status)
            
            let process = ProcessInfo(
                pid: cProcess.pid,
                name: name,
                cpuUsage: cProcess.cpu_usage,
                memoryMB: cProcess.memory_mb,
                status: status,
                parentPid: cProcess.parent_pid,
                threadCount: cProcess.thread_count,
                runTime: cProcess.run_time,
                userTime: cProcess.user_time,
                systemTime: cProcess.system_time,
                ioWaitTimeMs: cProcess.io_wait_time_ms,
                contextSwitches: cProcess.context_switches,
                minorFaults: cProcess.minor_faults,
                majorFaults: cProcess.major_faults,
                priority: cProcess.priority,
                isUnkillable: cProcess.is_unkillable != 0,
                isProblematic: cProcess.is_problematic != 0
            )
            highCpuProcs.append(process)
        }
        
        return highCpuProcs.sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    func terminateProcess(_ pid: UInt32) -> (success: Bool, message: String) {
        guard let response = terminate_process(pid) else {
            return (false, "Failed to execute termination")
        }
        defer { free_action_response(response) }
        
        let message = response.pointee.message != nil
            ? String(cString: response.pointee.message!)
            : "Unknown response"
        
        return (response.pointee.result == .success, message)
    }
    
    func forceKillProcess(_ pid: UInt32) -> (success: Bool, message: String) {
        guard let response = force_kill_process(pid) else {
            return (false, "Failed to execute kill")
        }
        defer { free_action_response(response) }
        
        let message = response.pointee.message != nil
            ? String(cString: response.pointee.message!)
            : "Unknown response"
        
        return (response.pointee.result == .success, message)
    }
    
    func suspendProcess(_ pid: UInt32) -> (success: Bool, message: String) {
        guard let response = suspend_process(pid) else {
            return (false, "Failed to execute suspend")
        }
        defer { free_action_response(response) }
        
        let message = response.pointee.message != nil
            ? String(cString: response.pointee.message!)
            : "Unknown response"
        
        return (response.pointee.result == .success, message)
    }
    
    func resumeProcess(_ pid: UInt32) -> (success: Bool, message: String) {
        guard let response = resume_process(pid) else {
            return (false, "Failed to execute resume")
        }
        defer { free_action_response(response) }
        
        let message = response.pointee.message != nil
            ? String(cString: response.pointee.message!)
            : "Unknown response"
        
        return (response.pointee.result == .success, message)
    }
    
    func getProcessDetails(_ pid: UInt32) async -> ProcessDetailsInfo? {
        guard let detailsPtr = get_process_details(pid) else { return nil }
        defer { free_process_details(detailsPtr) }
        
        let details = detailsPtr.pointee
        
        // Convert fields - some may be empty due to ProcessDetails limitations
        let path = details.exe_path != nil ? String(cString: details.exe_path!) : "Unknown"
        let commandLine = details.command_line != nil ? String(cString: details.command_line!) : ""
        let arguments = commandLine.isEmpty ? [] : commandLine.components(separatedBy: " ")
        
        // Open files count is available but not the list
        var openFiles: [String] = []
        if details.open_files_count > 0 {
            openFiles.append("\(details.open_files_count) files open")
        }
        
        // No connection info in simplified ProcessDetails
        let connections: [String] = []
        
        // User/group info not available in simplified version
        let user = "N/A"
        let group = "N/A"
        
        return ProcessDetailsInfo(
            pid: details.pid,
            executablePath: path,
            arguments: arguments,
            openFiles: openFiles,
            connections: connections,
            user: user,
            group: group
        )
    }
    
    nonisolated private func fetchMemoryMetricsSync() -> MemoryMetrics? {
        guard let metricsPtr = get_memory_info() else { return nil }
        defer { free_memory_info(metricsPtr) }
        
        let cMetrics = metricsPtr.pointee
        
        let pressure = safeStringFromCString(cMetrics.memory_pressure)
        
        return MemoryMetrics(
            totalBytes: cMetrics.total_bytes,
            usedBytes: cMetrics.used_bytes,
            availableBytes: cMetrics.available_bytes,
            freeBytes: cMetrics.free_bytes,
            swapTotalBytes: cMetrics.swap_total_bytes,
            swapUsedBytes: cMetrics.swap_used_bytes,
            swapFreeBytes: cMetrics.swap_free_bytes,
            cachedBytes: cMetrics.cached_bytes,
            bufferBytes: cMetrics.buffer_bytes,
            usagePercent: cMetrics.usage_percent,
            swapUsagePercent: cMetrics.swap_usage_percent,
            memoryPressure: pressure
        )
    }
    
    nonisolated private func fetchTopMemoryProcessesSync() -> [ProcessMemoryInfo] {
        guard let listPtr = get_top_memory_processes(10) else { return [] }
        defer { free_process_memory_list(listPtr) }
        
        return parseProcessMemoryList(listPtr)
    }
    
    nonisolated private func detectMemoryLeaksSync() -> [ProcessMemoryInfo] {
        guard let listPtr = detect_memory_leaks() else { return [] }
        defer { free_process_memory_list(listPtr) }
        
        return parseProcessMemoryList(listPtr)
    }
    
    nonisolated private func parseProcessMemoryList(_ listPtr: UnsafeMutablePointer<CProcessMemoryList>) -> [ProcessMemoryInfo] {
        let list = listPtr.pointee
        guard let processesPtr = list.processes else { return [] }
        
        var memoryProcesses: [ProcessMemoryInfo] = []
        
        for i in 0..<list.count {
            let cProcess = processesPtr[i]
            
            let name = safeStringFromCString(cProcess.name)
            
            let process = ProcessMemoryInfo(
                id: cProcess.pid,
                pid: cProcess.pid,
                name: name,
                memoryBytes: cProcess.memory_bytes,
                virtualMemoryBytes: cProcess.virtual_memory_bytes,
                memoryPercent: cProcess.memory_percent,
                isGrowing: cProcess.is_growing != 0,
                growthRateMBPerMin: cProcess.growth_rate_mb_per_min
            )
            memoryProcesses.append(process)
        }
        
        return memoryProcesses
    }
    
    // CPU Limiting functions
    func limitProcessCPU(_ pid: UInt32, maxPercent: Float) -> Bool {
        let result = limit_process_cpu(pid, maxPercent)
        if result == 0 {
            // Refresh limits after successful limit
            Task {
                await refreshCpuLimits()
            }
        }
        return result == 0
    }
    
    func removeProcessLimit(_ pid: UInt32) -> Bool {
        let result = remove_process_limit(pid)
        if result == 0 {
            // Refresh limits after successful removal
            Task {
                await refreshCpuLimits()
            }
        }
        return result == 0
    }
    
    func setProcessNice(_ pid: UInt32, niceValue: Int32) -> Bool {
        let result = set_process_nice(pid, niceValue)
        return result == 0
    }
    
    func limitProcessToPreset(_ pid: UInt32, preset: CPULimitPreset) -> Bool {
        return limitProcessCPU(pid, maxPercent: preset.percentage)
    }
    
    func hasProcessLimit(_ pid: UInt32) -> Bool {
        return has_process_limit(pid) != 0
    }
    
    func refreshCpuLimits() async {
        let limits = await fetchCpuLimitsSync()
        await MainActor.run {
            self.cpuLimitedProcesses = limits
            self.limitedProcessPids = Set(limits.map { $0.pid })
        }
    }
    
    nonisolated private func fetchHardwareMetricsSync() -> HardwareMetrics? {
        guard let metricsPtr = get_hardware_metrics() else { return nil }
        defer { free_hardware_metrics(metricsPtr) }
        
        let cMetrics = metricsPtr.pointee
        
        // Parse temperatures
        var temperatures: [TemperatureSensor] = []
        if let tempsPtr = cMetrics.temperatures, cMetrics.temperature_count > 0 {
            for i in 0..<cMetrics.temperature_count {
                let cTemp = tempsPtr[i]
                let name = safeStringFromCString(cTemp.name)
                
                temperatures.append(TemperatureSensor(
                    name: name,
                    valueCelsius: cTemp.value_celsius,
                    sensorType: SensorType(rawValue: cTemp.sensor_type) ?? .other,
                    isCritical: cTemp.is_critical != 0
                ))
            }
        }
        
        // Parse thermal state
        let thermalState = ThermalState(rawValue: cMetrics.thermal_state) ?? .normal
        
        // Parse power metrics
        let cpuPower = cMetrics.has_power_metrics != 0 ? cMetrics.cpu_power_watts : nil
        let gpuPower = cMetrics.has_power_metrics != 0 ? cMetrics.gpu_power_watts : nil
        let totalPower = cMetrics.has_power_metrics != 0 ? cMetrics.total_power_watts : nil
        
        return HardwareMetrics(
            temperatures: temperatures,
            cpuFrequencyMHz: cMetrics.cpu_frequency_mhz,
            thermalState: thermalState,
            cpuPowerWatts: cpuPower,
            gpuPowerWatts: gpuPower,
            totalPowerWatts: totalPower
        )
    }
    
    nonisolated private func fetchPrimaryDiskSync() -> DiskMetrics? {
        guard let diskPtr = get_primary_disk() else { return nil }
        defer { free_disk_info(diskPtr) }
        
        let cDisk = diskPtr.pointee
        
        let mountPoint = safeStringFromCString(cDisk.mount_point)
        let name = safeStringFromCString(cDisk.name)
        let fileSystem = safeStringFromCString(cDisk.file_system)
        let diskType = safeStringFromCString(cDisk.disk_type)
        
        return DiskMetrics(
            id: mountPoint,
            mountPoint: mountPoint,
            name: name,
            fileSystem: fileSystem,
            totalBytes: cDisk.total_bytes,
            availableBytes: cDisk.available_bytes,
            usedBytes: cDisk.used_bytes,
            usagePercent: cDisk.usage_percent,
            isRemovable: cDisk.is_removable != 0,
            diskType: diskType
        )
    }
    
    nonisolated private func fetchAllDisksSync() -> [DiskMetrics] {
        guard let listPtr = get_all_disks() else { return [] }
        defer { free_disk_list(listPtr) }
        
        let list = listPtr.pointee
        var disks: [DiskMetrics] = []
        
        guard let disksPtr = list.disks, list.count > 0 else { return disks }
        
        for i in 0..<list.count {
            let cDisk = disksPtr[i]
            
            let mountPoint = safeStringFromCString(cDisk.mount_point)
            let name = safeStringFromCString(cDisk.name)
            let fileSystem = safeStringFromCString(cDisk.file_system)
            let diskType = safeStringFromCString(cDisk.disk_type)
            
            let disk = DiskMetrics(
                id: mountPoint,
                mountPoint: mountPoint,
                name: name,
                fileSystem: fileSystem,
                totalBytes: cDisk.total_bytes,
                availableBytes: cDisk.available_bytes,
                usedBytes: cDisk.used_bytes,
                usagePercent: cDisk.usage_percent,
                isRemovable: cDisk.is_removable != 0,
                diskType: diskType
            )
            
            disks.append(disk)
        }
        
        return disks
    }
    
    nonisolated private func fetchNetworkMetricsSync() -> NetworkMetrics? {
        guard let metricsPtr = get_network_metrics() else { return nil }
        defer { free_network_metrics(metricsPtr) }
        
        let cMetrics = metricsPtr.pointee
        
        // Parse connections
        var connections: [NetworkConnection] = []
        if let connectionsPtr = cMetrics.connections.connections, cMetrics.connections.count > 0 {
            for i in 0..<cMetrics.connections.count {
                let cConn = connectionsPtr[i]
                
                let processName = safeStringFromCString(cConn.process_name)
                let localAddress = safeStringFromCString(cConn.local_address)
                let remoteAddress = safeStringFromCString(cConn.remote_address)
                let networkProtocol = safeStringFromCString(cConn.network_protocol)
                let state = safeStringFromCString(cConn.state)
                
                let connection = NetworkConnection(
                    id: "\(localAddress):\(cConn.local_port)-\(remoteAddress):\(cConn.remote_port)",
                    pid: cConn.pid >= 0 ? cConn.pid : nil,
                    processName: processName,
                    localAddress: localAddress,
                    localPort: cConn.local_port,
                    remoteAddress: remoteAddress,
                    remotePort: cConn.remote_port,
                    networkProtocol: networkProtocol,
                    state: state,
                    bytesSent: cConn.bytes_sent,
                    bytesReceived: cConn.bytes_received
                )
                connections.append(connection)
            }
        }
        
        // Parse active interfaces
        var activeInterfaces: [String] = []
        if let interfacesPtr = cMetrics.active_interfaces, cMetrics.interface_count > 0 {
            for i in 0..<cMetrics.interface_count {
                if let interfacePtr = interfacesPtr[i] {
                    let interfaceName = safeStringFromCString(interfacePtr)
                    activeInterfaces.append(interfaceName)
                }
            }
        }
        
        let bandwidth = BandwidthStats(
            currentUploadBps: cMetrics.bandwidth.current_upload_bps,
            currentDownloadBps: cMetrics.bandwidth.current_download_bps,
            peakUploadBps: cMetrics.bandwidth.peak_upload_bps,
            peakDownloadBps: cMetrics.bandwidth.peak_download_bps,
            averageUploadBps: cMetrics.bandwidth.average_upload_bps,
            averageDownloadBps: cMetrics.bandwidth.average_download_bps
        )
        
        return NetworkMetrics(
            connections: connections,
            bandwidth: bandwidth,
            totalBytesSent: cMetrics.total_bytes_sent,
            totalBytesReceived: cMetrics.total_bytes_received,
            packetsSent: cMetrics.packets_sent,
            packetsReceived: cMetrics.packets_received,
            activeInterfaces: activeInterfaces
        )
    }
    
    nonisolated private func fetchCpuLimitsSync() -> [CpuLimitInfo] {
        guard let listPtr = get_all_cpu_limits() else { return [] }
        defer { free_cpu_limits(listPtr) }
        
        let list = listPtr.pointee
        guard let limitsPtr = list.limits else { return [] }
        
        var cpuLimits: [CpuLimitInfo] = []
        
        for i in 0..<list.count {
            let cLimit = limitsPtr[i]
            
            let limit = CpuLimitInfo(
                id: cLimit.pid,
                pid: cLimit.pid,
                maxCpuPercent: cLimit.max_cpu_percent,
                niceValue: cLimit.nice_value,
                limitType: CpuLimitInfo.CpuLimitType(rawValue: cLimit.limit_type)
            )
            cpuLimits.append(limit)
        }
        
        return cpuLimits
    }
    
    
    // MARK: - Process Tree Methods
    
    func fetchProcessTree(completion: @escaping ([ProcessTreeNode]) -> Void) async {
        let roots = await Task.detached { () -> [ProcessTreeNode] in
            guard let treePtr = get_process_tree() else {
                return []
            }
            
            defer { free_process_tree(treePtr) }
            
            let cTree = treePtr.assumingMemoryBound(to: CProcessTree.self).pointee
            
            var roots: [ProcessTreeNode] = []
            
            if let rootsPtr = cTree.roots {
                for i in 0..<cTree.roots_count {
                    let cNode = rootsPtr[i]
                    if let node = await Self.convertTreeNode(cNode) {
                        roots.append(node)
                    }
                }
            }
            
            return roots
        }.value
        
        await MainActor.run {
            completion(roots)
        }
    }
    
    private static func convertTreeNode(_ cNode: CProcessTreeNode) -> ProcessTreeNode? {
        let name = cNode.name.map { String(cString: $0) } ?? "Unknown"
        let status = cNode.status.map { String(cString: $0) } ?? "Unknown"
        let executablePath = cNode.executable_path.map { String(cString: $0) } ?? ""
        
        // Convert command array
        var command: [String] = []
        if let cmdPtr = cNode.command {
            for i in 0..<cNode.command_count {
                if let argPtr = cmdPtr[i] {
                    command.append(String(cString: argPtr))
                }
            }
        }
        
        // Convert children recursively
        var children: [ProcessTreeNode] = []
        if let childrenPtr = cNode.children {
            for i in 0..<cNode.children_count {
                let childCNode = childrenPtr[i]
                if let childNode = convertTreeNode(childCNode) {
                    children.append(childNode)
                }
            }
        }
        
        return ProcessTreeNode(
            id: cNode.pid,
            pid: cNode.pid,
            name: name,
            command: command,
            executablePath: executablePath,
            cpuUsage: cNode.cpu_usage,
            memoryMB: cNode.memory_mb,
            status: status,
            threadCount: cNode.thread_count,
            children: children,
            totalCpuUsage: cNode.total_cpu_usage,
            totalMemoryMB: cNode.total_memory_mb,
            descendantCount: cNode.descendant_count
        )
    }
}