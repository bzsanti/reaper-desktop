import SwiftUI
import Charts

struct MemoryView: View {
    @ObservedObject var rustBridge: RustBridge
    @State private var selectedTab = 0
    @State private var showLeaksOnly = false
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Top Processes").tag(1)
                Text("Memory Leaks").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            switch selectedTab {
            case 0:
                overviewTab
            case 1:
                topProcessesTab
            case 2:
                memoryLeaksTab
            default:
                EmptyView()
            }
        }
    }
    
    var headerView: some View {
        VStack(spacing: 12) {
            if let metrics = rustBridge.memoryMetrics {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memory Usage")
                            .font(.headline)
                        Text(formatBytes(metrics.usedBytes) + " / " + formatBytes(metrics.totalBytes))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(Int(metrics.usagePercent))% used")
                            .font(.caption)
                            .foregroundColor(colorForUsage(metrics.usagePercent))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Swap")
                            .font(.headline)
                        Text(formatBytes(metrics.swapUsedBytes) + " / " + formatBytes(metrics.swapTotalBytes))
                            .font(.title3)
                        Text("\(Int(metrics.swapUsagePercent))% used")
                            .font(.caption)
                            .foregroundColor(colorForUsage(metrics.swapUsagePercent))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memory Pressure")
                            .font(.headline)
                        HStack {
                            Circle()
                                .fill(colorForPressure(metrics.memoryPressure))
                                .frame(width: 12, height: 12)
                            Text(metrics.memoryPressure)
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
    }
    
    var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let metrics = rustBridge.memoryMetrics {
                    // Memory usage chart
                    memoryUsageChart(metrics)
                        .padding()
                    
                    // Memory breakdown
                    memoryBreakdown(metrics)
                        .padding()
                    
                    // Memory pressure indicator
                    memoryPressureIndicator(metrics)
                        .padding()
                }
            }
        }
    }
    
    @ViewBuilder
    func memoryUsageChart(_ metrics: MemoryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Distribution")
                .font(.headline)
            
            // Custom circular progress view for macOS 13 compatibility
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 40)
                    .frame(width: 180, height: 180)
                
                Circle()
                    .trim(from: 0, to: CGFloat(metrics.usagePercent / 100))
                    .stroke(
                        LinearGradient(
                            colors: [colorForUsage(metrics.usagePercent), colorForUsage(metrics.usagePercent).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 40, lineCap: .round)
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: metrics.usagePercent)
                
                VStack {
                    Text("\(Int(metrics.usagePercent))%")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 200)
            
            HStack(spacing: 20) {
                Label(formatBytes(metrics.usedBytes) + " Used", systemImage: "circle.fill")
                    .foregroundColor(colorForUsage(metrics.usagePercent))
                Label(formatBytes(metrics.availableBytes) + " Available", systemImage: "circle.fill")
                    .foregroundColor(.gray)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    func memoryBreakdown(_ metrics: MemoryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Breakdown")
                .font(.headline)
            
            VStack(spacing: 8) {
                memoryRow("Total", value: metrics.totalBytes, color: .primary)
                memoryRow("Used", value: metrics.usedBytes, color: .blue)
                memoryRow("Available", value: metrics.availableBytes, color: .green)
                memoryRow("Free", value: metrics.freeBytes, color: .gray)
                
                Divider()
                
                memoryRow("Swap Total", value: metrics.swapTotalBytes, color: .primary)
                memoryRow("Swap Used", value: metrics.swapUsedBytes, color: .orange)
                memoryRow("Swap Free", value: metrics.swapFreeBytes, color: .gray)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    func memoryRow(_ label: String, value: UInt64, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(formatBytes(value))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    @ViewBuilder
    func memoryPressureIndicator(_ metrics: MemoryMetrics) -> some View {
        VStack(spacing: 12) {
            Text("System Memory Pressure")
                .font(.headline)
            
            HStack(spacing: 8) {
                ForEach(["Low", "Normal", "High", "Critical"], id: \.self) { level in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(metrics.memoryPressure == level ? colorForPressure(level) : Color.gray.opacity(0.3))
                            .frame(width: 30, height: 30)
                        Text(level)
                            .font(.caption2)
                            .foregroundColor(metrics.memoryPressure == level ? .primary : .secondary)
                    }
                }
            }
            
            if metrics.memoryPressure == "High" || metrics.memoryPressure == "Critical" {
                Text("⚠️ High memory pressure detected. Consider closing unused applications.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    var topProcessesTab: some View {
        VStack(spacing: 0) {
            if rustBridge.topMemoryProcesses.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No process memory data available")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rustBridge.topMemoryProcesses) { process in
                    ProcessMemoryRow(process: process)
                }
            }
        }
    }
    
    var memoryLeaksTab: some View {
        VStack(spacing: 0) {
            if rustBridge.memoryLeaks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No memory leaks detected")
                        .font(.title2)
                    Text("All processes have stable memory usage")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Potential Memory Leaks Detected")
                            .font(.headline)
                    }
                    .padding()
                    
                    Text("These processes show continuous memory growth:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    List(rustBridge.memoryLeaks) { process in
                        MemoryLeakRow(process: process)
                    }
                }
            }
        }
    }
    
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func colorForUsage(_ percent: Float) -> Color {
        switch percent {
        case 0..<50:
            return .green
        case 50..<75:
            return .orange
        case 75..<90:
            return .red
        default:
            return .red
        }
    }
    
    func colorForPressure(_ pressure: String) -> Color {
        switch pressure {
        case "Low":
            return .green
        case "Normal":
            return .blue
        case "High":
            return .orange
        case "Critical":
            return .red
        default:
            return .gray
        }
    }
}

struct ProcessMemoryRow: View {
    let process: ProcessMemoryInfo
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(process.name)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)
                    
                    Text("PID: \(process.pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                
                HStack(spacing: 12) {
                    Label(formatMemory(process.memoryMB), systemImage: "memorychip")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    if process.memoryPercent > 0 {
                        Text(String(format: "%.1f%%", process.memoryPercent))
                            .font(.caption)
                            .foregroundColor(colorForMemoryUsage(process.memoryPercent))
                    }
                    
                    if process.isGrowing {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.caption)
                            Text(String(format: "+%.1f MB/min", process.growthRateMBPerMin))
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            ProgressView(value: Double(process.memoryPercent), total: 100)
                .progressViewStyle(.linear)
                .frame(width: 100)
        }
        .padding(.vertical, 4)
    }
    
    func formatMemory(_ mb: Double) -> String {
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024)
        }
    }
    
    func colorForMemoryUsage(_ percent: Float) -> Color {
        switch percent {
        case 0..<5:
            return .green
        case 5..<10:
            return .blue
        case 10..<20:
            return .orange
        default:
            return .red
        }
    }
}

struct MemoryLeakRow: View {
    let process: ProcessMemoryInfo
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(process.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Text("PID: \(process.pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(String(format: "%.1f MB", process.memoryMB), systemImage: "memorychip")
                        .font(.caption)
                    
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                        Text(String(format: "+%.2f MB/min", process.growthRateMBPerMin))
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}