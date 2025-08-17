import SwiftUI
import Charts

struct HighCpuView: View {
    @ObservedObject var rustBridge: RustBridge
    @State private var selectedProcesses = Set<UInt32>()
    @State private var sortOrder = [KeyPathComparator(\ProcessInfo.cpuUsage, order: .reverse)]
    @State private var showSettings = false
    @State private var cpuHistory: [UInt32: [Float]] = [:]
    @State private var refreshTimer: Timer?
    
    @StateObject private var notificationManager = NotificationManager()
    @EnvironmentObject var appState: AppState
    
    var highCpuProcesses: [ProcessInfo] {
        let filtered = rustBridge.processes.filter { $0.cpuUsage >= appState.highCpuThreshold }
        return filtered.sorted(using: sortOrder)
    }
    
    var groupedProcesses: [(String, [ProcessInfo], Float)] {
        guard appState.groupProcessesByApp else { 
            return highCpuProcesses.map { ($0.name, [$0], $0.cpuUsage) }
        }
        
        let grouped = Dictionary(grouping: highCpuProcesses) { process in
            process.name.components(separatedBy: " ").first ?? process.name
        }
        
        return grouped.map { (key, processes) in
            let totalCpu = processes.reduce(0) { $0 + $1.cpuUsage }
            return (key, processes, totalCpu)
        }.sorted { $0.2 > $1.2 }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            if highCpuProcesses.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    if appState.showCpuTrendChart {
                        cpuTrendChart
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                    }
                    
                    Divider()
                    
                    processTable
                }
            }
        }
        .onAppear {
            startHistoryTracking()
        }
        .onDisappear {
            stopHistoryTracking()
        }
        .sheet(isPresented: $showSettings) {
            HighCpuSettingsView(
                threshold: $appState.highCpuThreshold,
                groupByApp: $appState.groupProcessesByApp
            )
        }
        .withNotifications(notificationManager)
    }
    
    var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("High CPU Processes")
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack(spacing: 12) {
                    Label("\(highCpuProcesses.count) processes", systemImage: "flame")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("Threshold: \(Int(appState.highCpuThreshold))%", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let totalCpu = rustBridge.cpuMetrics?.totalUsage {
                        Label("Total: \(String(format: "%.1f%%", totalCpu))", systemImage: "cpu")
                            .font(.caption)
                            .foregroundColor(colorForCpuUsage(totalCpu))
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Toggle(isOn: $appState.groupProcessesByApp) {
                    Image(systemName: "square.grid.3x1.folder.badge.plus")
                }
                .toggleStyle(.button)
                .help("Group by Application")
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Settings")
                
                Button(action: { rustBridge.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("No High CPU Processes")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("All processes are below \(Int(appState.highCpuThreshold))% CPU usage")
                .foregroundColor(.secondary)
            
            Button(action: { showSettings = true }) {
                Label("Adjust Threshold", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(60)
    }
    
    var cpuTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CPU Usage Trend (60s)")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { withAnimation { appState.showCpuTrendChart.toggle() } }) {
                    Image(systemName: appState.showCpuTrendChart ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if !cpuHistory.isEmpty {
                Chart {
                    ForEach(Array(highCpuProcesses.prefix(5)), id: \.pid) { process in
                        if let history = cpuHistory[process.pid], !history.isEmpty {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, value in
                                LineMark(
                                    x: .value("Time", index),
                                    y: .value("CPU %", value),
                                    series: .value("Process", process.name)
                                )
                                .foregroundStyle(by: .value("Process", process.name))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 10)) { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(60 - intValue)s")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)%")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
            } else {
                Text("Collecting data...")
                    .foregroundColor(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    var processTable: some View {
        Table(highCpuProcesses, selection: $selectedProcesses, sortOrder: $sortOrder) {
            TableColumn("") { process in
                Image(systemName: iconForCpuLevel(process.cpuUsage))
                    .foregroundColor(colorForCpuUsage(process.cpuUsage))
                    .font(.caption)
            }
            .width(20)
            
            TableColumn("PID", value: \.pid) { process in
                Text("\(process.pid)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(60)
            
            TableColumn("Name", value: \.name) { process in
                HStack {
                    Text(process.name)
                        .lineLimit(1)
                    
                    if process.isProblematic {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .help("Problematic process")
                    }
                }
            }
            .width(min: 150, ideal: 250, max: 400)
            
            TableColumn("CPU %", value: \.cpuUsage) { process in
                HStack {
                    Text(String(format: "%.1f", process.cpuUsage))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(colorForCpuUsage(process.cpuUsage))
                    
                    ProgressView(value: Double(process.cpuUsage), total: 100)
                        .progressViewStyle(.linear)
                        .tint(colorForCpuUsage(process.cpuUsage))
                        .frame(width: 60)
                    
                    if let trend = cpuTrend(for: process.pid) {
                        Image(systemName: trend)
                            .foregroundColor(trend == "arrow.up" ? .red : .green)
                            .font(.caption)
                    }
                }
            }
            .width(140)
            
            TableColumn("Memory", value: \.memoryMB) { process in
                Text(formatMemory(process.memoryMB))
                    .font(.system(.body, design: .monospaced))
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
            
            TableColumn("Impact") { process in
                HStack(spacing: 4) {
                    if process.contextSwitches > 10000 {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .help("High context switches")
                    }
                    
                    if process.ioWaitTimeMs > 1000 {
                        Image(systemName: "hourglass")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .help("High I/O wait")
                    }
                    
                    if process.isUnkillable {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .help("Unkillable process")
                    }
                }
            }
            .width(80)
        }
        .contextMenu(forSelectionType: ProcessInfo.ID.self) { pids in
            contextMenuItems(for: Array(pids))
        } primaryAction: { pids in
            if let pid = pids.first,
               let process = highCpuProcesses.first(where: { $0.pid == pid }) {
                appState.selectedProcess = process
                appState.shouldShowDetails = true
            }
        }
    }
    
    @ViewBuilder
    func contextMenuItems(for pids: [UInt32]) -> some View {
        if pids.count == 1,
           let pid = pids.first,
           let process = highCpuProcesses.first(where: { $0.pid == pid }) {
            
            Button(action: { terminateProcess(process) }) {
                Label("Terminate Process", systemImage: "stop.circle")
            }
            
            Button(action: { forceKillProcess(process) }) {
                Label("Force Kill", systemImage: "xmark.circle.fill")
            }
            .foregroundColor(.red)
            
            Divider()
            
            Button(action: { suspendProcess(process) }) {
                Label("Suspend", systemImage: "pause.circle")
            }
            
            Button(action: { resumeProcess(process) }) {
                Label("Resume", systemImage: "play.circle")
            }
            
            Divider()
            
            Button(action: { copyProcessInfo(process) }) {
                Label("Copy Info", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                appState.selectedProcess = process
                appState.shouldShowDetails = true
            }) {
                Label("Show Details", systemImage: "info.circle")
            }
            
        } else if pids.count > 1 {
            Button(action: { terminateSelectedProcesses(pids) }) {
                Label("Terminate \(pids.count) Processes", systemImage: "stop.circle")
            }
            
            Button(action: { suspendSelectedProcesses(pids) }) {
                Label("Suspend \(pids.count) Processes", systemImage: "pause.circle")
            }
        }
    }
    
    func startHistoryTracking() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                updateCpuHistory()
            }
        }
    }
    
    func stopHistoryTracking() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func updateCpuHistory() {
        for process in highCpuProcesses {
            if cpuHistory[process.pid] == nil {
                cpuHistory[process.pid] = []
            }
            
            cpuHistory[process.pid]?.append(process.cpuUsage)
            
            if cpuHistory[process.pid]?.count ?? 0 > 60 {
                cpuHistory[process.pid]?.removeFirst()
            }
        }
        
        cpuHistory = cpuHistory.filter { pid, _ in
            highCpuProcesses.contains { $0.pid == pid }
        }
    }
    
    func cpuTrend(for pid: UInt32) -> String? {
        guard let history = cpuHistory[pid], history.count > 5 else { return nil }
        
        let recent = Array(history.suffix(5))
        let average = recent.reduce(0, +) / Float(recent.count)
        let current = history.last ?? 0
        
        if current > average * 1.2 {
            return "arrow.up"
        } else if current < average * 0.8 {
            return "arrow.down"
        }
        return nil
    }
    
    func iconForCpuLevel(_ usage: Float) -> String {
        switch usage {
        case 0..<50:
            return "flame"
        case 50..<75:
            return "flame.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
    
    func colorForCpuUsage(_ usage: Float) -> Color {
        switch usage {
        case 0..<50:
            return .orange
        case 50..<75:
            return .red
        default:
            return .red
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
    
    func terminateProcess(_ process: ProcessInfo) {
        appState.processToAct = process
        appState.showTerminateConfirmation = true
    }
    
    func forceKillProcess(_ process: ProcessInfo) {
        appState.processToAct = process
        appState.showForceKillConfirmation = true
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
    
    func copyProcessInfo(_ process: ProcessInfo) {
        let info = """
        Process: \(process.name)
        PID: \(process.pid)
        CPU: \(String(format: "%.1f%%", process.cpuUsage))
        Memory: \(formatMemory(process.memoryMB))
        Threads: \(process.threadCount)
        Runtime: \(formatRuntime(process.runTime))
        Context Switches: \(process.contextSwitches)
        I/O Wait: \(process.ioWaitTimeMs)ms
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        
        notificationManager.show(
            .info,
            title: "Copied to Clipboard",
            message: "Process information copied"
        )
    }
    
    func terminateSelectedProcesses(_ pids: [UInt32]) {
        let processes = highCpuProcesses.filter { pids.contains($0.pid) }
        
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
        }
    }
    
    func suspendSelectedProcesses(_ pids: [UInt32]) {
        let processes = highCpuProcesses.filter { pids.contains($0.pid) }
        
        var successCount = 0
        
        for process in processes {
            if rustBridge.suspendProcess(process.pid) {
                successCount += 1
            }
        }
        
        if successCount > 0 {
            notificationManager.show(
                .success,
                title: "Batch Suspend Complete",
                message: "Successfully suspended \(successCount) process(es)"
            )
            rustBridge.refresh()
        }
    }
}

struct HighCpuSettingsView: View {
    @Binding var threshold: Float
    @Binding var groupByApp: Bool
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Text("High CPU Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("CPU Threshold")
                    .font(.headline)
                
                HStack {
                    Slider(value: $threshold, in: 5...100, step: 5)
                    Text("\(Int(threshold))%")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                }
                
                Text("Processes using more than \(Int(threshold))% CPU will be shown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Group by Application", isOn: $groupByApp)
                    .font(.headline)
                
                Text("Combine processes from the same application")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Done") {
                    appState.savePreferences()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}