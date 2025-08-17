import SwiftUI

struct ProcessListView: View {
    @ObservedObject var rustBridge: RustBridge
    @Binding var searchText: String
    @Binding var selectedProcess: ProcessInfo?
    @Binding var showingDetails: Bool
    @State private var displayedProcesses: [ProcessInfo] = []
    @State private var selectedProcesses = Set<UInt32>()
    @State private var sortOrder = [KeyPathComparator(\ProcessInfo.cpuUsage, order: .reverse)]
    
    // Notification system
    @StateObject private var notificationManager = NotificationManager()
    
    // App State
    @EnvironmentObject var appState: AppState
    
    var filteredProcesses: [ProcessInfo] {
        let filtered = searchText.isEmpty ? displayedProcesses : displayedProcesses.filter { process in
            process.name.localizedCaseInsensitiveContains(searchText) ||
            String(process.pid).contains(searchText)
        }
        return filtered.sorted(using: sortOrder)
    }
    
    var processTable: some View {
        return Table(filteredProcesses, selection: $selectedProcesses, sortOrder: $sortOrder) {
            TableColumn("PID", value: \.pid) { process in
                Text("\(process.pid)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 50, ideal: appState.columnWidths["pid"] ?? 60, max: 120)
            
            TableColumn("Name", value: \.name) { process in
                HStack {
                    Image(systemName: iconForProcess(process))
                        .foregroundColor(.secondary)
                    Text(process.name)
                        .lineLimit(1)
                    
                    // CPU Limit indicator
                    if rustBridge.limitedProcessPids.contains(process.pid) {
                        if let limit = rustBridge.cpuLimitedProcesses.first(where: { $0.pid == process.pid }) {
                            Image(systemName: "gauge.badge.minus")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .help("CPU Limited to \(Int(limit.maxCpuPercent))%")
                        }
                    }
                    
                    Spacer()
                }
            }
            .width(min: 150, ideal: appState.columnWidths["name"] ?? 250, max: 400)
            
            TableColumn("CPU %", value: \.cpuUsage) { process in
                HStack {
                    Text(String(format: "%.1f", process.cpuUsage))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(colorForCpuUsage(process.cpuUsage))
                    
                    if process.cpuUsage > 0 {
                        ProgressView(value: Double(process.cpuUsage), total: 100)
                            .progressViewStyle(.linear)
                            .frame(width: 50)
                    }
                }
            }
            .width(120)
            
            TableColumn("Memory", value: \.memoryMB) { process in
                Text(formatMemory(process.memoryMB))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 100, ideal: appState.columnWidths["memory"] ?? 120, max: 180)
            
            TableColumn("Status", value: \.status) { process in
                HStack(spacing: 4) {
                    // Icon for special states
                    if process.isUnkillable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .help("Unkillable process")
                    } else if process.isProblematic {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .help("Problematic process")
                    }
                    
                    Text(process.status)
                        .font(.caption)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(backgroundColorForStatus(process.status, isUnkillable: process.isUnkillable, isProblematic: process.isProblematic))
                .cornerRadius(4)
            }
            .width(min: 80, ideal: appState.columnWidths["status"] ?? 100, max: 120)
            
            TableColumn("Threads", value: \.threadCount) { process in
                Text("\(process.threadCount)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 60, ideal: appState.columnWidths["threads"] ?? 80, max: 100)
            
            TableColumn("Runtime", value: \.runTime) { process in
                Text(formatRuntime(process.runTime))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 80, ideal: appState.columnWidths["runtime"] ?? 100, max: 150)
            
            TableColumn("Parent PID", value: \.parentPid) { process in
                Text("\(process.parentPid)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: appState.columnWidths["parent_pid"] ?? 80, max: 100)
            
            TableColumn("User Time", value: \.userTime) { process in
                Text(String(format: "%.2fs", process.userTime))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
            }
            .width(min: 60, ideal: appState.columnWidths["user_time"] ?? 80, max: 120)
            
            TableColumn("System Time", value: \.systemTime) { process in
                Text(String(format: "%.2fs", process.systemTime))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .width(min: 60, ideal: appState.columnWidths["system_time"] ?? 80, max: 120)
        }
    }
    
    var body: some View {
        processTable
        .contextMenu(forSelectionType: ProcessInfo.ID.self) { pids in
            let selectedPids = Array(pids)
            
            if selectedPids.count == 1 {
                // Single process selection
                if let pid = selectedPids.first,
                   let process = filteredProcesses.first(where: { $0.pid == pid }) {
                    
                    // CPU Limiting menu
                    cpuLimitMenu(for: process)
                    
                    Button(action: {
                        reduceProcessPriority(process)
                    }) {
                        Label("Reduce Priority", systemImage: "arrow.down.circle")
                    }
                    .disabled(process.pid == UInt32(Foundation.ProcessInfo.processInfo.processIdentifier))
                    
                    Divider()
                    
                    Button(action: {
                        terminateProcess(process)
                    }) {
                        Label("Terminate Process", systemImage: "stop.circle")
                    }
                    
                    Button(action: {
                        forceKillProcess(process)
                    }) {
                        Label("Force Kill", systemImage: "xmark.circle.fill")
                    }
                    .foregroundColor(.red)
                    
                    Divider()
                    
                    Button(action: {
                        suspendProcess(process)
                    }) {
                        Label("Suspend", systemImage: "pause.circle")
                    }
                    
                    Button(action: {
                        resumeProcess(process)
                    }) {
                        Label("Resume", systemImage: "play.circle")
                    }
                    
                    Divider()
                    
                    Button(action: {
                        copyProcessInfo(process)
                    }) {
                        Label("Copy Info", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: {
                        showInActivityMonitor(process)
                    }) {
                        Label("Show in Activity Monitor", systemImage: "arrow.up.forward.app")
                    }
                }
            } else if selectedPids.count > 1 {
                // Multiple process selection - batch operations
                Button(action: {
                    terminateSelectedProcesses(selectedPids)
                }) {
                    Label("Terminate \(selectedPids.count) Processes", systemImage: "stop.circle")
                }
                
                Button(action: {
                    suspendSelectedProcesses(selectedPids)
                }) {
                    Label("Suspend \(selectedPids.count) Processes", systemImage: "pause.circle")
                }
                
                Button(action: {
                    resumeSelectedProcesses(selectedPids)
                }) {
                    Label("Resume \(selectedPids.count) Processes", systemImage: "play.circle")
                }
                
                Divider()
                
                Button(action: {
                    copySelectedProcessesInfo(selectedPids)
                }) {
                    Label("Copy Info for \(selectedPids.count) Processes", systemImage: "doc.on.doc")
                }
            }
        } primaryAction: { pids in
            if let pid = pids.first,
               let process = filteredProcesses.first(where: { $0.pid == pid }) {
                selectedProcess = process
                showingDetails = true
            }
        }
        .onReceive(rustBridge.$processes) { newProcesses in
            displayedProcesses = newProcesses
        }
        .onAppear {
            displayedProcesses = rustBridge.processes
        }
        .onChange(of: selectedProcesses) { newSelection in
            // When selection changes, update the selected process
            if let pid = newSelection.first,
               let process = filteredProcesses.first(where: { $0.pid == pid }) {
                selectedProcess = process
            }
        }
        .onChange(of: sortOrder) { _ in
            // Save sort preferences when sort order changes
            appState.savePreferences()
        }
        .withNotifications(notificationManager)
        .sheet(isPresented: $appState.showTerminateConfirmation) {
            if let process = appState.processToAct {
                ProcessActionConfirmation(
                    process: process,
                    action: .terminate,
                    onConfirm: {
                        performTerminate(process)
                    },
                    isPresented: $appState.showTerminateConfirmation
                )
            }
        }
        .sheet(isPresented: $appState.showForceKillConfirmation) {
            if let process = appState.processToAct {
                ProcessActionConfirmation(
                    process: process,
                    action: .forceKill,
                    onConfirm: {
                        performForceKill(process)
                    },
                    isPresented: $appState.showForceKillConfirmation
                )
            }
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    func cpuLimitMenu(for process: ProcessInfo) -> some View {
        let hasLimit = rustBridge.limitedProcessPids.contains(process.pid)
        let currentLimit = rustBridge.cpuLimitedProcesses.first(where: { $0.pid == process.pid })
        
        Menu {
            if hasLimit, let limit = currentLimit {
                Text("Currently limited to \(Int(limit.maxCpuPercent))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
            }
            
            ForEach(CPULimitPreset.allCases, id: \.self) { preset in
                Button(action: {
                    limitProcessCPU(process, preset: preset)
                }) {
                    if let limit = currentLimit, Int(limit.maxCpuPercent) == Int(preset.percentage) {
                        Label("✓ Limit to \(preset.description)", systemImage: "checkmark")
                    } else {
                        Label("Limit to \(preset.description)", systemImage: "speedometer")
                    }
                }
            }
            
            if hasLimit {
                Divider()
                
                Button(action: {
                    removeProcessLimit(process)
                }) {
                    Label("Remove CPU Limit", systemImage: "xmark.circle")
                }
            }
        } label: {
            if hasLimit {
                Label("CPU Limited", systemImage: "gauge.badge.minus")
                    .foregroundColor(.orange)
            } else {
                Label("Limit CPU Usage", systemImage: "gauge.badge.minus")
            }
        }
        .disabled(process.pid == UInt32(Foundation.ProcessInfo.processInfo.processIdentifier))
    }
    
    // MARK: - Actions
    
    func terminateProcess(_ process: ProcessInfo) {
        appState.processToAct = process
        appState.showTerminateConfirmation = true
    }
    
    func performTerminate(_ process: ProcessInfo) {
        let result = rustBridge.terminateProcess(process.pid)
        
        if result.success {
            notificationManager.show(
                .success,
                title: "Process Terminated",
                message: "\(process.name) (PID: \(process.pid)) was terminated successfully"
            )
            rustBridge.refresh()
        } else {
            notificationManager.show(
                .error,
                title: "Failed to Terminate",
                message: result.message
            )
        }
    }
    
    func forceKillProcess(_ process: ProcessInfo) {
        appState.processToAct = process
        appState.showForceKillConfirmation = true
    }
    
    func performForceKill(_ process: ProcessInfo) {
        let result = rustBridge.forceKillProcess(process.pid)
        
        if result.success {
            notificationManager.show(
                .success,
                title: "Process Killed",
                message: "\(process.name) (PID: \(process.pid)) was forcefully terminated"
            )
            rustBridge.refresh()
        } else {
            notificationManager.show(
                .error,
                title: "Failed to Kill Process",
                message: result.message
            )
        }
    }
    
    func suspendProcess(_ process: ProcessInfo) {
        let success = rustBridge.suspendProcess(process.pid)
        
        if success {
            notificationManager.show(
                .success,
                title: "Process Suspended",
                message: "\(process.name) (PID: \(process.pid)) was suspended"
            )
            rustBridge.refresh()
        } else {
            notificationManager.show(
                .error,
                title: "Failed to Suspend",
                message: "Could not suspend \(process.name)"
            )
        }
    }
    
    func resumeProcess(_ process: ProcessInfo) {
        let success = rustBridge.resumeProcess(process.pid)
        
        if success {
            notificationManager.show(
                .success,
                title: "Process Resumed",
                message: "\(process.name) (PID: \(process.pid)) was resumed"
            )
            rustBridge.refresh()
        } else {
            notificationManager.show(
                .error,
                title: "Failed to Resume",
                message: "Could not resume \(process.name)"
            )
        }
    }
    
    func limitProcessCPU(_ process: ProcessInfo, preset: CPULimitPreset) {
        let success = rustBridge.limitProcessToPreset(process.pid, preset: preset)
        
        if success {
            notificationManager.show(
                .success,
                title: "CPU Limit Applied",
                message: "\(process.name) limited to \(preset.description)"
            )
        } else {
            notificationManager.show(
                .error,
                title: "Failed to Apply Limit",
                message: "Could not limit CPU for \(process.name). May require elevated privileges."
            )
        }
    }
    
    func removeProcessLimit(_ process: ProcessInfo) {
        let success = rustBridge.removeProcessLimit(process.pid)
        
        if success {
            notificationManager.show(
                .info,
                title: "CPU Limit Removed",
                message: "CPU limit removed from \(process.name)"
            )
        } else {
            notificationManager.show(
                .warning,
                title: "No Limit Found",
                message: "\(process.name) has no CPU limit applied"
            )
        }
    }
    
    func reduceProcessPriority(_ process: ProcessInfo) {
        let success = rustBridge.setProcessNice(process.pid, niceValue: 10)
        
        if success {
            notificationManager.show(
                .success,
                title: "Priority Reduced",
                message: "\(process.name) priority has been lowered"
            )
        } else {
            notificationManager.show(
                .error,
                title: "Failed to Change Priority",
                message: "Could not change priority for \(process.name)"
            )
        }
    }
    
    func copyProcessInfo(_ process: ProcessInfo) {
        let info = """
        Process: \(process.name)
        PID: \(process.pid)
        CPU: \(String(format: "%.1f%%", process.cpuUsage))
        Memory: \(formatMemory(process.memoryMB))
        Status: \(process.status)
        Threads: \(process.threadCount)
        Runtime: \(formatRuntime(process.runTime))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        
        notificationManager.show(
            .info,
            title: "Copied to Clipboard",
            message: "Process information copied"
        )
    }
    
    func showInActivityMonitor(_ process: ProcessInfo) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    
    // MARK: - Batch Operations
    
    func terminateSelectedProcesses(_ pids: [UInt32]) {
        let processes = filteredProcesses.filter { pids.contains($0.pid) }
        let systemProcesses = processes.filter { $0.pid < 100 }
        
        if !systemProcesses.isEmpty {
            notificationManager.show(
                .warning,
                title: "System Processes Detected",
                message: "Terminating system processes can cause system instability. Operation cancelled."
            )
            return
        }
        
        var successCount = 0
        var failureCount = 0
        
        for process in processes {
            let result = rustBridge.terminateProcess(process.pid)
            if result.success {
                successCount += 1
            } else {
                failureCount += 1
            }
        }
        
        if successCount > 0 {
            notificationManager.show(
                .success,
                title: "Batch Terminate Complete",
                message: "Successfully terminated \(successCount) process(es)" + 
                        (failureCount > 0 ? ", \(failureCount) failed" : "")
            )
            rustBridge.refresh()
        } else {
            notificationManager.show(
                .error,
                title: "Batch Terminate Failed",
                message: "Failed to terminate any of the selected processes"
            )
        }
    }
    
    func suspendSelectedProcesses(_ pids: [UInt32]) {
        let processes = filteredProcesses.filter { pids.contains($0.pid) }
        let systemProcesses = processes.filter { $0.pid < 100 }
        
        if !systemProcesses.isEmpty {
            notificationManager.show(
                .warning,
                title: "System Processes Detected",
                message: "Suspending system processes can cause system instability. Operation cancelled."
            )
            return
        }
        
        var successCount = 0
        var failureCount = 0
        
        for process in processes {
            let success = rustBridge.suspendProcess(process.pid)
            if success {
                successCount += 1
            } else {
                failureCount += 1
            }
        }
        
        if successCount > 0 {
            notificationManager.show(
                .success,
                title: "Batch Suspend Complete",
                message: "Successfully suspended \(successCount) process(es)" + 
                        (failureCount > 0 ? ", \(failureCount) failed" : "")
            )
            rustBridge.refresh()
        } else {
            notificationManager.show(
                .error,
                title: "Batch Suspend Failed",
                message: "Failed to suspend any of the selected processes"
            )
        }
    }
    
    func resumeSelectedProcesses(_ pids: [UInt32]) {
        let processes = filteredProcesses.filter { pids.contains($0.pid) }
        
        var successCount = 0
        var failureCount = 0
        
        for process in processes {
            let success = rustBridge.resumeProcess(process.pid)
            if success {
                successCount += 1
            } else {
                failureCount += 1
            }
        }
        
        if successCount > 0 {
            notificationManager.show(
                .success,
                title: "Batch Resume Complete",
                message: "Successfully resumed \(successCount) process(es)" + 
                        (failureCount > 0 ? ", \(failureCount) failed" : "")
            )
            rustBridge.refresh()
        } else {
            notificationManager.show(
                .error,
                title: "Batch Resume Failed",
                message: "Failed to resume any of the selected processes"
            )
        }
    }
    
    func copySelectedProcessesInfo(_ pids: [UInt32]) {
        let processes = filteredProcesses.filter { pids.contains($0.pid) }
        
        let info = processes.map { process in
            """
            Process: \(process.name)
            PID: \(process.pid)
            CPU: \(String(format: "%.1f%%", process.cpuUsage))
            Memory: \(formatMemory(process.memoryMB))
            Status: \(process.status)
            Threads: \(process.threadCount)
            Runtime: \(formatRuntime(process.runTime))
            Parent PID: \(process.parentPid)
            User Time: \(String(format: "%.2fs", process.userTime))
            System Time: \(String(format: "%.2fs", process.systemTime))
            """
        }.joined(separator: "\n\n---\n\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        
        notificationManager.show(
            .info,
            title: "Copied to Clipboard",
            message: "Information for \(processes.count) process(es) copied"
        )
    }
    
    // MARK: - Helpers
    
    func iconForProcess(_ process: ProcessInfo) -> String {
        if process.status.contains("Zombie") {
            return "exclamationmark.triangle.fill"
        } else if process.status.contains("Run") {
            return "play.circle.fill"
        } else if process.status.contains("Sleep") || process.status.contains("Idle") {
            return "moon.zzz"
        } else {
            return "circle"
        }
    }
    
    func colorForCpuUsage(_ usage: Float) -> Color {
        switch usage {
        case 0..<25:
            return .primary
        case 25..<50:
            return .blue
        case 50..<75:
            return .orange
        default:
            return .red
        }
    }
    
    func backgroundColorForStatus(_ status: String, isUnkillable: Bool = false, isProblematic: Bool = false) -> Color {
        // Priority for unkillable processes
        if isUnkillable {
            return .red.opacity(0.3)
        } else if isProblematic {
            return .orange.opacity(0.3)
        } else if status.contains("Run") {
            return .green.opacity(0.2)
        } else if status.contains("Zombie") {
            return .red.opacity(0.2)
        } else if status.contains("Uninterruptible") {
            return .orange.opacity(0.2)
        } else {
            return .gray.opacity(0.1)
        }
    }
    
    func formatMemory(_ mb: Double) -> String {
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024)
        }
    }
    
    func formatRuntime(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    func formatIOWaitTime(_ ms: UInt64) -> String {
        if ms == 0 {
            return "-"
        } else if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            let minutes = ms / 60000
            let seconds = (ms % 60000) / 1000
            return String(format: "%02d:%02ds", minutes, seconds)
        }
    }
}