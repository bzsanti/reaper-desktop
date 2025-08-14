import SwiftUI
import Charts

struct HighCpuView: View {
    @ObservedObject var rustBridge: RustBridge
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if rustBridge.highCpuProcesses.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("No High CPU Processes")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("All processes are running within normal CPU usage limits")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    Text("High CPU Processes")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    Chart(rustBridge.highCpuProcesses.prefix(10)) { process in
                        BarMark(
                            x: .value("CPU %", process.cpuUsage),
                            y: .value("Process", process.name)
                        )
                        .foregroundStyle(gradientForCpuUsage(process.cpuUsage))
                        .annotation(position: .trailing) {
                            Text(String(format: "%.1f%%", process.cpuUsage))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: CGFloat(min(rustBridge.highCpuProcesses.count, 10)) * 40)
                    .padding(.horizontal)
                    
                    Divider()
                        .padding(.horizontal)
                    
                    ForEach(rustBridge.highCpuProcesses, id: \.pid) { process in
                        ProcessCard(process: process)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    func gradientForCpuUsage(_ usage: Float) -> LinearGradient {
        let colors: [Color] = usage > 75 ? [.orange, .red] : 
                              usage > 50 ? [.yellow, .orange] : 
                              [.blue, .green]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

struct ProcessCard: View {
    let process: ProcessInfo
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(process.name)
                            .font(.headline)
                        Text("PID: \(process.pid)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    HStack(spacing: 16) {
                        Label(String(format: "%.1f%% CPU", process.cpuUsage), 
                              systemImage: "cpu")
                            .font(.caption)
                            .foregroundColor(colorForCpuUsage(process.cpuUsage))
                        
                        Label(formatMemory(process.memoryMB), 
                              systemImage: "memorychip")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Label("\(process.threadCount) threads", 
                              systemImage: "square.stack.3d.up")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
                
                Spacer()
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "Status", value: process.status)
                    DetailRow(label: "Parent PID", value: String(process.parentPid))
                    DetailRow(label: "Runtime", value: formatRuntime(process.runTime))
                }
                .padding()
                .background(Color.gray.opacity(0.05))
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    func colorForCpuUsage(_ usage: Float) -> Color {
        usage > 75 ? .red : usage > 50 ? .orange : .green
    }
    
    func formatMemory(_ mb: Double) -> String {
        mb < 1024 ? String(format: "%.1f MB", mb) : String(format: "%.2f GB", mb / 1024)
    }
    
    func formatRuntime(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? 
            String(format: "%dh %dm", hours, minutes) : 
            String(format: "%dm", minutes)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}