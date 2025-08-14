import Foundation

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

class RustBridge: ObservableObject {
    @Published var processes: [ProcessInfo] = []
    @Published var cpuMetrics: CpuMetrics?
    @Published var highCpuProcesses: [ProcessInfo] = []
    
    private var refreshTimer: Timer?
    
    init() {
        monitor_init()
        startRefreshTimer()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.refresh()
        }
    }
    
    func refresh() {
        monitor_refresh()
        fetchProcesses()
        fetchCpuMetrics()
        fetchHighCpuProcesses()
    }
    
    private func fetchProcesses() {
        guard let listPtr = get_all_processes() else { return }
        defer { free_process_list(listPtr) }
        
        let list = listPtr.pointee
        guard let processesPtr = list.processes else { return }
        
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
        
        DispatchQueue.main.async {
            self.processes = newProcesses.sorted { $0.cpuUsage > $1.cpuUsage }
        }
    }
    
    private func fetchCpuMetrics() {
        guard let metricsPtr = get_cpu_metrics() else { return }
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
        
        DispatchQueue.main.async {
            self.cpuMetrics = metrics
        }
    }
    
    private func fetchHighCpuProcesses() {
        guard let listPtr = get_high_cpu_processes(25.0) else { return }
        defer { free_process_list(listPtr) }
        
        let list = listPtr.pointee
        guard let processesPtr = list.processes else { return }
        
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
        
        DispatchQueue.main.async {
            self.highCpuProcesses = highCpuProcs.sorted { $0.cpuUsage > $1.cpuUsage }
        }
    }
}