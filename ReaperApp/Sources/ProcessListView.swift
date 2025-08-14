import SwiftUI

struct ProcessListView: View {
    @ObservedObject var rustBridge: RustBridge
    @Binding var searchText: String
    @State private var displayedProcesses: [ProcessInfo] = []
    @State private var selectedProcesses = Set<UInt32>()
    @State private var sortOrder = [KeyPathComparator(\ProcessInfo.cpuUsage, order: .reverse)]
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var processToKill: ProcessInfo?
    
    var filteredProcesses: [ProcessInfo] {
        let filtered = searchText.isEmpty ? displayedProcesses : displayedProcesses.filter { process in
            process.name.localizedCaseInsensitiveContains(searchText) ||
            String(process.pid).contains(searchText)
        }
        return filtered.sorted(using: sortOrder)
    }
    
    var body: some View {
        Table(filteredProcesses, selection: $selectedProcesses, sortOrder: $sortOrder) {
            TableColumn("PID", value: \.pid) { process in
                Text("\(process.pid)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(60)
            
            TableColumn("Name", value: \.name) { process in
                HStack {
                    Image(systemName: iconForProcess(process))
                        .foregroundColor(.secondary)
                    Text(process.name)
                        .lineLimit(1)
                }
            }
            .width(min: 200)
            
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
            .width(100)
            
            TableColumn("Status", value: \.status) { process in
                Text(process.status)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(backgroundColorForStatus(process.status))
                    .cornerRadius(4)
            }
            .width(100)
            
            TableColumn("Threads", value: \.threadCount) { process in
                Text("\(process.threadCount)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(80)
            
            TableColumn("Runtime", value: \.runTime) { process in
                Text(formatRuntime(process.runTime))
                    .font(.system(.body, design: .monospaced))
            }
            .width(100)
        }
        .contextMenu(forSelectionType: ProcessInfo.ID.self) { pids in
            if let pid = pids.first {
                if let process = filteredProcesses.first(where: { $0.pid == pid }) {
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
            }
        } primaryAction: { pids in
            if let pid = pids.first,
               let process = filteredProcesses.first(where: { $0.pid == pid }) {
                showProcessDetails(process)
            }
        }
        .onReceive(rustBridge.$processes) { newProcesses in
            displayedProcesses = newProcesses
        }
        .onAppear {
            displayedProcesses = rustBridge.processes
        }
        .alert("Process Action", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog("Terminate Process?", isPresented: .constant(processToKill != nil)) {
            if let process = processToKill {
                Button("Terminate \(process.name)", role: .destructive) {
                    performTerminate(process)
                }
                Button("Cancel", role: .cancel) {
                    processToKill = nil
                }
            }
        } message: {
            if let process = processToKill {
                Text("Are you sure you want to terminate \(process.name) (PID: \(process.pid))?")
            }
        }
    }
    
    // MARK: - Actions
    
    func terminateProcess(_ process: ProcessInfo) {
        processToKill = process
    }
    
    func performTerminate(_ process: ProcessInfo) {
        let result = rustBridge.terminateProcess(process.pid)
        alertMessage = result.message
        showingAlert = true
        processToKill = nil
        if result.success {
            rustBridge.refresh()
        }
    }
    
    func forceKillProcess(_ process: ProcessInfo) {
        let result = rustBridge.forceKillProcess(process.pid)
        alertMessage = result.message
        showingAlert = true
        if result.success {
            rustBridge.refresh()
        }
    }
    
    func suspendProcess(_ process: ProcessInfo) {
        let success = rustBridge.suspendProcess(process.pid)
        alertMessage = success ? "Process suspended" : "Failed to suspend process"
        showingAlert = true
        if success {
            rustBridge.refresh()
        }
    }
    
    func resumeProcess(_ process: ProcessInfo) {
        let success = rustBridge.resumeProcess(process.pid)
        alertMessage = success ? "Process resumed" : "Failed to resume process"
        showingAlert = true
        if success {
            rustBridge.refresh()
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
    }
    
    func showInActivityMonitor(_ process: ProcessInfo) {
        NSWorkspace.shared.launchApplication("Activity Monitor")
    }
    
    func showProcessDetails(_ process: ProcessInfo) {
        // This will be implemented with ProcessDetailView
        print("Show details for \(process.name)")
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
    
    func backgroundColorForStatus(_ status: String) -> Color {
        if status.contains("Run") {
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
}