import SwiftUI
import AppKit

struct ProcessDetailView: View {
    let process: ProcessInfo
    @ObservedObject var rustBridge: RustBridge
    @State private var expandedSections = Set<String>()
    @State private var processDetails: ExtendedProcessInfo?
    @State private var isLoadingDetails = false
    @State private var lastLoadedPid: UInt32 = 0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection
                
                Divider()
                
                // Basic Info
                basicInfoSection
                
                // CPU & Memory
                performanceSection
                
                // Extended Details (lazy loaded)
                if isLoadingDetails {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading process details...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                } else if let details = processDetails {
                    extendedDetailsSection(details)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Unable to load details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            loadExtendedDetails()
                        }
                        .buttonStyle(.link)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            if lastLoadedPid != process.pid {
                processDetails = nil
                expandedSections.removeAll()
                loadExtendedDetails()
            }
        }
        .onChange(of: process.pid) { newPid in
            print("[DEBUG] Process changed from \(lastLoadedPid) to \(newPid)")
            if lastLoadedPid != newPid {
                processDetails = nil
                expandedSections.removeAll()
                loadExtendedDetails()
            }
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForProcess(process))
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text(process.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("PID: \(process.pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Refresh button
                Button(action: {
                    processDetails = nil
                    loadExtendedDetails()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingDetails)
                .help("Refresh details")
                
                // Status Badge
                Text(process.status)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(backgroundColorForStatus(process.status))
                    .cornerRadius(6)
            }
        }
    }
    
    private var basicInfoSection: some View {
        DisclosureGroup(
            isExpanded: binding(for: "basic")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ProcessDetailRow(label: "Process ID", value: String(process.pid))
                ProcessDetailRow(label: "Parent PID", value: String(process.parentPid))
                ProcessDetailRow(label: "Threads", value: String(process.threadCount))
                ProcessDetailRow(label: "Runtime", value: formatRuntime(process.runTime))
                ProcessDetailRow(label: "Status", value: process.status)
                if let details = processDetails {
                    ProcessDetailRow(label: "User", value: details.user)
                    ProcessDetailRow(label: "Group", value: details.group)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Basic Information", systemImage: "info.circle")
                .font(.headline)
        }
    }
    
    private var performanceSection: some View {
        DisclosureGroup(
            isExpanded: binding(for: "performance")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // CPU Usage with mini graph
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU Usage")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuUsage))
                            .fontWeight(.medium)
                            .foregroundColor(colorForCpuUsage(process.cpuUsage))
                    }
                    
                    ProgressView(value: Double(process.cpuUsage), total: 100)
                        .progressViewStyle(.linear)
                        .tint(colorForCpuUsage(process.cpuUsage))
                }
                
                Divider()
                
                // Memory Usage
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Memory")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatMemory(process.memoryMB))
                            .fontWeight(.medium)
                    }
                    
                    if process.memoryMB < 10000 {
                        ProgressView(value: process.memoryMB, total: 10000)
                            .progressViewStyle(.linear)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Performance", systemImage: "speedometer")
                .font(.headline)
        }
    }
    
    private func extendedDetailsSection(_ details: ExtendedProcessInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Executable Path
            DisclosureGroup(
                isExpanded: binding(for: "path")
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.executablePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    
                    HStack {
                        Button("Show in Finder") {
                            showInFinder(details.executablePath)
                        }
                        .buttonStyle(.link)
                        
                        Button("Copy Path") {
                            copyToClipboard(details.executablePath)
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Executable Path", systemImage: "doc.text")
                    .font(.headline)
            }
            
            // Command Line Arguments
            if !details.arguments.isEmpty {
                DisclosureGroup(
                    isExpanded: binding(for: "arguments")
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(details.arguments.enumerated()), id: \.offset) { index, arg in
                            HStack(alignment: .top) {
                                Text("\(index):")
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                                Text(arg)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Arguments (\(details.arguments.count))", systemImage: "terminal")
                        .font(.headline)
                }
            }
            
            // Environment Variables
            if !details.environment.isEmpty {
                DisclosureGroup(
                    isExpanded: binding(for: "environment")
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(details.environment.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack(alignment: .top) {
                                Text(key)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(.accentColor)
                                Text("=")
                                    .foregroundColor(.secondary)
                                Text(value)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Environment (\(details.environment.count))", systemImage: "leaf")
                        .font(.headline)
                }
            }
            
            // Open Files
            DisclosureGroup(
                isExpanded: binding(for: "files")
            ) {
                if details.openFiles.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("No open files detected or requires elevated permissions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(details.openFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: iconForFile(file))
                                    .foregroundColor(.secondary)
                                Text(file)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            } label: {
                HStack {
                    Label("Open Files", systemImage: "folder")
                        .font(.headline)
                    if !details.openFiles.isEmpty {
                        Text("(\(details.openFiles.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Network Connections
            DisclosureGroup(
                isExpanded: binding(for: "network")
            ) {
                if details.connections.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("No active network connections")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(details.connections, id: \.self) { connection in
                            HStack {
                                Image(systemName: "network")
                                    .foregroundColor(.secondary)
                                Text(connection)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            } label: {
                HStack {
                    Label("Network", systemImage: "network")
                        .font(.headline)
                    if !details.connections.isEmpty {
                        Text("(\(details.connections.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func binding(for section: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }
    
    private func loadExtendedDetails() {
        isLoadingDetails = true
        
        let pid = process.pid
        lastLoadedPid = pid
        print("[DEBUG] Loading details for PID: \(pid)")
        
        // Get real process details from Rust
        Task { @MainActor in
            if let details = await rustBridge.getProcessDetails(pid) {
                self.processDetails = ExtendedProcessInfo(
                    pid: details.pid,
                    executablePath: details.executablePath,
                    arguments: details.arguments,
                    environment: [:], // Environment vars might need elevated permissions
                    openFiles: details.openFiles,
                    connections: details.connections,
                    user: details.user,
                    group: details.group
                )
                self.isLoadingDetails = false
                
                // Auto-expand basic and performance sections
                self.expandedSections.insert("basic")
                self.expandedSections.insert("performance")
                
                // Auto-expand sections with content
                if !details.arguments.isEmpty {
                    self.expandedSections.insert("arguments")
                }
                if !details.openFiles.isEmpty {
                    self.expandedSections.insert("files")
                }
                if !details.connections.isEmpty {
                    self.expandedSections.insert("network")
                }
            } else {
                // Failed to get details
                self.processDetails = ExtendedProcessInfo(
                    pid: self.process.pid,
                    executablePath: "Unable to retrieve path",
                    arguments: [],
                    environment: [:],
                    openFiles: [],
                    connections: [],
                    user: "unknown",
                    group: "unknown"
                )
                self.isLoadingDetails = false
                self.expandedSections.insert("basic")
            }
        }
    }
    
    private func showInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func iconForFile(_ path: String) -> String {
        if path.contains("/tmp") || path.contains("socket") {
            return "link"
        } else if path.contains("/dev") {
            return "terminal"
        } else {
            return "doc"
        }
    }
    
    // Reuse helper functions from ProcessListView
    private func iconForProcess(_ process: ProcessInfo) -> String {
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
    
    private func colorForCpuUsage(_ usage: Float) -> Color {
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
    
    private func backgroundColorForStatus(_ status: String) -> Color {
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
    
    private func formatMemory(_ mb: Double) -> String {
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024)
        }
    }
    
    private func formatRuntime(_ seconds: UInt64) -> String {
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

// MARK: - Supporting Views

struct ProcessDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Data Models

struct ExtendedProcessInfo {
    let pid: UInt32
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let openFiles: [String]
    let connections: [String]
    let user: String
    let group: String
}