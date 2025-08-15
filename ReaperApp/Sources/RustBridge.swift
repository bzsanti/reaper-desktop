import Foundation
import AppKit

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
    
    init(pid: UInt32, name: String, cpuUsage: Float, memoryMB: Double, status: String, parentPid: UInt32, threadCount: Int, runTime: UInt64) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.cpuUsage = cpuUsage
        self.memoryMB = memoryMB
        self.status = status
        self.parentPid = parentPid
        self.threadCount = threadCount
        self.runTime = runTime
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

@_silgen_name("monitor_init")
func monitor_init()

@_silgen_name("monitor_refresh")
func monitor_refresh()

@_silgen_name("get_all_processes")
func get_all_processes() -> UnsafeMutablePointer<CProcessList>?

@_silgen_name("get_high_cpu_processes")
func get_high_cpu_processes(_ threshold: Float) -> UnsafeMutablePointer<CProcessList>?

@_silgen_name("get_cpu_metrics")
func get_cpu_metrics() -> UnsafeMutablePointer<CCpuMetrics>?

@_silgen_name("free_process_list")
func free_process_list(_ list: UnsafeMutablePointer<CProcessList>?)

@_silgen_name("free_cpu_metrics")
func free_cpu_metrics(_ metrics: UnsafeMutablePointer<CCpuMetrics>?)

@_silgen_name("terminate_process")
func terminate_process(_ pid: UInt32) -> CKillResult

@_silgen_name("force_kill_process")
func force_kill_process(_ pid: UInt32) -> CKillResult

@_silgen_name("suspend_process")
func suspend_process(_ pid: UInt32) -> Bool

@_silgen_name("resume_process")
func resume_process(_ pid: UInt32) -> Bool

@_silgen_name("get_process_details")
func get_process_details(_ pid: UInt32) -> UnsafeMutablePointer<CProcessDetails>?

@_silgen_name("free_process_details")
func free_process_details(_ details: UnsafeMutablePointer<CProcessDetails>?)

enum CKillResult: Int32 {
    case success = 0
    case processNotFound = 1
    case permissionDenied = 2
    case processUnkillable = 3
    case unknownError = 4
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
    var executable_path: UnsafeMutablePointer<CChar>?
    var arguments: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var arguments_count: Int
    var open_files: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var open_files_count: Int
    var connections: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var connections_count: Int
    var user: UnsafeMutablePointer<CChar>?
    var group: UnsafeMutablePointer<CChar>?
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

@MainActor
class RustBridge: ObservableObject {
    @Published var processes: [ProcessInfo] = []
    @Published var cpuMetrics: CpuMetrics?
    @Published var highCpuProcesses: [ProcessInfo] = []
    
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
                    
                    let newProcesses = self.fetchProcessesSync()
                    let newMetrics = self.fetchCpuMetricsSync()
                    let newHighCpuProcesses = self.fetchHighCpuProcessesSync()
                    
                    Task { @MainActor in
                        self.processes = newProcesses
                        self.cpuMetrics = newMetrics
                        self.highCpuProcesses = newHighCpuProcesses
                        
                        // Adjust refresh rate based on activity
                        self.adjustRefreshRate()
                        self.isUpdating = false
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    nonisolated private func fetchProcessesSync() -> [ProcessInfo] {
        guard let listPtr = get_all_processes() else { return [] }
        defer { free_process_list(listPtr) }
        
        let list = listPtr.pointee
        guard let processesPtr = list.processes else { return [] }
        
        var newProcesses: [ProcessInfo] = []
        
        for i in 0..<list.count {
            let cProcess = processesPtr[i]
            let name = cProcess.name.map { String(cString: $0) } ?? "Unknown"
            let status = cProcess.status.map { String(cString: $0) } ?? "Unknown"
            
            let process = ProcessInfo(
                pid: cProcess.pid,
                name: name,
                cpuUsage: cProcess.cpu_usage,
                memoryMB: cProcess.memory_mb,
                status: status,
                parentPid: cProcess.parent_pid,
                threadCount: cProcess.thread_count,
                runTime: cProcess.run_time
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
            let name = cProcess.name.map { String(cString: $0) } ?? "Unknown"
            let status = cProcess.status.map { String(cString: $0) } ?? "Unknown"
            
            let process = ProcessInfo(
                pid: cProcess.pid,
                name: name,
                cpuUsage: cProcess.cpu_usage,
                memoryMB: cProcess.memory_mb,
                status: status,
                parentPid: cProcess.parent_pid,
                threadCount: cProcess.thread_count,
                runTime: cProcess.run_time
            )
            highCpuProcs.append(process)
        }
        
        return highCpuProcs.sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    func terminateProcess(_ pid: UInt32) -> (success: Bool, message: String) {
        let result = terminate_process(pid)
        switch result {
        case .success:
            return (true, "Process terminated successfully")
        case .processNotFound:
            return (false, "Process not found")
        case .permissionDenied:
            return (false, "Permission denied. Try running with sudo.")
        case .processUnkillable:
            return (false, "Process cannot be terminated (kernel process or I/O blocked)")
        case .unknownError:
            return (false, "Unknown error occurred")
        }
    }
    
    func forceKillProcess(_ pid: UInt32) -> (success: Bool, message: String) {
        let result = force_kill_process(pid)
        switch result {
        case .success:
            return (true, "Process killed successfully")
        case .processNotFound:
            return (false, "Process not found")
        case .permissionDenied:
            return (false, "Permission denied. Try running with sudo.")
        case .processUnkillable:
            return (false, "Process cannot be killed (kernel process)")
        case .unknownError:
            return (false, "Unknown error occurred")
        }
    }
    
    func suspendProcess(_ pid: UInt32) -> Bool {
        return suspend_process(pid)
    }
    
    func resumeProcess(_ pid: UInt32) -> Bool {
        return resume_process(pid)
    }
    
    func getProcessDetails(_ pid: UInt32) async -> ProcessDetailsInfo? {
        guard let detailsPtr = get_process_details(pid) else { return nil }
        defer { free_process_details(detailsPtr) }
        
        let details = detailsPtr.pointee
        
        // Convert executable path
        let path = details.executable_path.map { String(cString: $0) } ?? ""
        
        // Convert arguments
        var arguments: [String] = []
        if let argsPtr = details.arguments, details.arguments_count > 0 {
            for i in 0..<details.arguments_count {
                if let argPtr = argsPtr[i] {
                    arguments.append(String(cString: argPtr))
                }
            }
        }
        
        // Convert open files
        var openFiles: [String] = []
        if let filesPtr = details.open_files, details.open_files_count > 0 {
            for i in 0..<details.open_files_count {
                if let filePtr = filesPtr[i] {
                    openFiles.append(String(cString: filePtr))
                }
            }
        }
        
        // Convert connections
        var connections: [String] = []
        if let connsPtr = details.connections, details.connections_count > 0 {
            for i in 0..<details.connections_count {
                if let connPtr = connsPtr[i] {
                    connections.append(String(cString: connPtr))
                }
            }
        }
        
        // Convert user and group
        let user = details.user.map { String(cString: $0) } ?? "unknown"
        let group = details.group.map { String(cString: $0) } ?? "unknown"
        
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
}