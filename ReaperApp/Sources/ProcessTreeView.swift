import SwiftUI

// MARK: - Process Tree Node Model
struct ProcessTreeNode: Identifiable {
    let id: UInt32
    let pid: UInt32
    let name: String
    let command: [String]
    let executablePath: String
    let cpuUsage: Float
    let memoryMB: Double
    let status: String
    let threadCount: Int
    var children: [ProcessTreeNode]
    let totalCpuUsage: Float
    let totalMemoryMB: Double
    let descendantCount: Int
    
    var displayName: String {
        if !command.isEmpty && command[0] != name {
            // Show full command for things like shell scripts
            return command.joined(separator: " ")
        }
        return name
    }
    
    var commandLine: String {
        command.joined(separator: " ")
    }
    
    var hasChildren: Bool {
        !children.isEmpty
    }
}

// MARK: - Tree Row View
struct ProcessTreeRowView: View {
    let node: ProcessTreeNode
    let depth: Int
    @State private var isExpanded: Bool = true
    @Binding var selectedPids: Set<UInt32>
    @Binding var searchText: String
    
    private var isHighlighted: Bool {
        if searchText.isEmpty { return false }
        return node.name.localizedCaseInsensitiveContains(searchText) ||
               node.commandLine.localizedCaseInsensitiveContains(searchText) ||
               String(node.pid).contains(searchText)
    }
    
    private var shouldShowNode: Bool {
        if searchText.isEmpty { return true }
        return isHighlighted || hasHighlightedDescendant(node)
    }
    
    private func hasHighlightedDescendant(_ node: ProcessTreeNode) -> Bool {
        for child in node.children {
            if child.name.localizedCaseInsensitiveContains(searchText) ||
               child.commandLine.localizedCaseInsensitiveContains(searchText) ||
               String(child.pid).contains(searchText) {
                return true
            }
            if hasHighlightedDescendant(child) {
                return true
            }
        }
        return false
    }
    
    var body: some View {
        if shouldShowNode {
            VStack(alignment: .leading, spacing: 0) {
                // Main row
                HStack(spacing: 4) {
                    // Indentation
                    ForEach(0..<depth, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                    }
                    
                    // Expand/collapse button
                    if node.hasChildren {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 16)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 16)
                    }
                    
                    // Process info
                    HStack {
                        // Selection checkbox
                        Button(action: {
                            if selectedPids.contains(node.pid) {
                                selectedPids.remove(node.pid)
                            } else {
                                selectedPids.insert(node.pid)
                            }
                        }) {
                            Image(systemName: selectedPids.contains(node.pid) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14))
                                .foregroundColor(selectedPids.contains(node.pid) ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        // PID
                        Text(String(node.pid))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        
                        // Name/Command
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name)
                                .font(.system(.body))
                                .fontWeight(isHighlighted ? .semibold : .regular)
                                .foregroundColor(isHighlighted ? .accentColor : .primary)
                            
                            if !node.command.isEmpty && node.command.count > 1 {
                                Text(node.commandLine)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // CPU Usage
                        HStack(spacing: 4) {
                            if node.hasChildren {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "%.1f%%", node.totalCpuUsage))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(colorForCpu(node.totalCpuUsage))
                                    Text(String(format: "(%.1f%%)", node.cpuUsage))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(String(format: "%.1f%%", node.cpuUsage))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(colorForCpu(node.cpuUsage))
                            }
                        }
                        .frame(width: 80, alignment: .trailing)
                        
                        // Memory
                        HStack(spacing: 4) {
                            if node.hasChildren {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formatMemory(node.totalMemoryMB))
                                        .font(.system(.caption, design: .monospaced))
                                    Text(formatMemory(node.memoryMB))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(formatMemory(node.memoryMB))
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .frame(width: 100, alignment: .trailing)
                        
                        // Status
                        Text(node.status)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(backgroundForStatus(node.status))
                            .cornerRadius(4)
                            .frame(width: 80)
                        
                        // Thread count
                        if node.threadCount > 0 {
                            Text("\(node.threadCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedPids.contains(node.pid) ? 
                                  Color.accentColor.opacity(0.1) : 
                                  Color.clear)
                    )
                }
                
                // Children (if expanded)
                if isExpanded && node.hasChildren {
                    ForEach(node.children) { child in
                        ProcessTreeRowView(
                            node: child,
                            depth: depth + 1,
                            selectedPids: $selectedPids,
                            searchText: $searchText
                        )
                    }
                }
            }
        }
    }
    
    private func colorForCpu(_ usage: Float) -> Color {
        switch usage {
        case 0..<25:
            return .green
        case 25..<50:
            return .yellow
        case 50..<75:
            return .orange
        default:
            return .red
        }
    }
    
    private func formatMemory(_ mb: Double) -> String {
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.1f GB", mb / 1024.0)
        }
    }
    
    private func backgroundForStatus(_ status: String) -> Color {
        if status.contains("Running") {
            return .green.opacity(0.2)
        } else if status.contains("Sleep") {
            return .blue.opacity(0.2)
        } else if status.contains("Zombie") {
            return .red.opacity(0.2)
        } else {
            return .gray.opacity(0.2)
        }
    }
}

// MARK: - Main Tree View
struct ProcessTreeView: View {
    @ObservedObject var rustBridge: RustBridge
    @Binding var searchText: String
    @State private var processTree: [ProcessTreeNode] = []
    @State private var selectedPids = Set<UInt32>()
    @State private var expandAll: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Process Tree")
                    .font(.headline)
                
                Spacer()
                
                // Expand/Collapse All button
                Button(action: {
                    expandAll.toggle()
                }) {
                    Label(expandAll ? "Collapse All" : "Expand All", 
                          systemImage: expandAll ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                // Selection info
                if !selectedPids.isEmpty {
                    Text("\(selectedPids.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                    
                    Button("Clear") {
                        selectedPids.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            // Tree content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(processTree) { rootNode in
                        ProcessTreeRowView(
                            node: rootNode,
                            depth: 0,
                            selectedPids: $selectedPids,
                            searchText: $searchText
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            loadProcessTree()
        }
        .task {
            // Refresh periodically
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                loadProcessTree()
            }
        }
    }
    
    private func loadProcessTree() {
        // This will be connected to the Rust backend
        // For now, creating mock data
        Task {
            await rustBridge.fetchProcessTree { tree in
                self.processTree = tree
            }
        }
    }
}