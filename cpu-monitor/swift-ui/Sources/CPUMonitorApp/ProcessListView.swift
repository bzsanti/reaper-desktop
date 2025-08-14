import SwiftUI

struct ProcessListView: View {
    @ObservedObject var rustBridge: RustBridge
    @Binding var searchText: String
    
    var filteredProcesses: [ProcessInfo] {
        if searchText.isEmpty {
            return rustBridge.processes
        } else {
            return rustBridge.processes.filter { process in
                process.name.localizedCaseInsensitiveContains(searchText) ||
                String(process.pid).contains(searchText)
            }
        }
    }
    
    var body: some View {
        Table(filteredProcesses) {
            TableColumn("PID") { process in
                Text("\(process.pid)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(60)
            
            TableColumn("Name") { process in
                HStack {
                    Image(systemName: iconForProcess(process))
                        .foregroundColor(.secondary)
                    Text(process.name)
                        .lineLimit(1)
                }
            }
            .width(min: 200)
            
            TableColumn("CPU %") { process in
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
            
            TableColumn("Memory") { process in
                Text(formatMemory(process.memoryMB))
                    .font(.system(.body, design: .monospaced))
            }
            .width(100)
            
            TableColumn("Status") { process in
                Text(process.status)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(backgroundColorForStatus(process.status))
                    .cornerRadius(4)
            }
            .width(100)
            
            TableColumn("Threads") { process in
                Text("\(process.threadCount)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(80)
            
            TableColumn("Runtime") { process in
                Text(formatRuntime(process.runTime))
                    .font(.system(.body, design: .monospaced))
            }
            .width(100)
        }
    }
    
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