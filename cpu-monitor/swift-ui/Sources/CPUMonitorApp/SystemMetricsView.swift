import SwiftUI
import Charts

struct SystemMetricsView: View {
    @ObservedObject var rustBridge: RustBridge
    @State private var cpuHistory: [CpuDataPoint] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let metrics = rustBridge.cpuMetrics {
                    cpuOverviewCard(metrics)
                    
                    loadAverageCard(metrics)
                    
                    systemInfoCard(metrics)
                }
            }
            .padding()
        }
        .onReceive(rustBridge.$cpuMetrics) { metrics in
            guard let metrics = metrics else { return }
            cpuHistory.append(CpuDataPoint(
                time: Date(),
                usage: Double(metrics.totalUsage)
            ))
            if cpuHistory.count > 60 {
                cpuHistory.removeFirst()
            }
        }
    }
    
    func cpuOverviewCard(_ metrics: CpuMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU Usage")
                .font(.title3)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                CircularProgressView(
                    progress: Double(metrics.totalUsage) / 100,
                    label: "Total",
                    value: String(format: "%.1f%%", metrics.totalUsage)
                )
                .frame(width: 120, height: 120)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("CPU Cores: \(metrics.coreCount)")
                        .font(.headline)
                    
                    if metrics.frequencyMHz > 0 {
                        Text("Frequency: \(formatFrequency(metrics.frequencyMHz))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Active Processes: \(rustBridge.processes.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if !cpuHistory.isEmpty {
                Chart(cpuHistory) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("CPU %", point.usage)
                    )
                    .foregroundStyle(.blue)
                    
                    AreaMark(
                        x: .value("Time", point.time),
                        y: .value("CPU %", point.usage)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
                .frame(height: 100)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    func loadAverageCard(_ metrics: CpuMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Load Average")
                .font(.title3)
                .fontWeight(.semibold)
            
            HStack(spacing: 30) {
                LoadAverageItem(
                    label: "1 min",
                    value: metrics.loadAverage1,
                    cores: metrics.coreCount
                )
                
                LoadAverageItem(
                    label: "5 min",
                    value: metrics.loadAverage5,
                    cores: metrics.coreCount
                )
                
                LoadAverageItem(
                    label: "15 min",
                    value: metrics.loadAverage15,
                    cores: metrics.coreCount
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    func systemInfoCard(_ metrics: CpuMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Information")
                .font(.title3)
                .fontWeight(.semibold)
            
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 40, verticalSpacing: 12) {
                GridRow {
                    Text("Total Processes")
                        .foregroundColor(.secondary)
                    Text("\(rustBridge.processes.count)")
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("High CPU Processes")
                        .foregroundColor(.secondary)
                    Text("\(rustBridge.highCpuProcesses.count)")
                        .fontWeight(.medium)
                        .foregroundColor(rustBridge.highCpuProcesses.isEmpty ? .green : .orange)
                }
                
                GridRow {
                    Text("CPU Cores")
                        .foregroundColor(.secondary)
                    Text("\(metrics.coreCount)")
                        .fontWeight(.medium)
                }
                
                if metrics.frequencyMHz > 0 {
                    GridRow {
                        Text("CPU Frequency")
                            .foregroundColor(.secondary)
                        Text(formatFrequency(metrics.frequencyMHz))
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    func formatFrequency(_ mhz: UInt64) -> String {
        if mhz >= 1000 {
            return String(format: "%.2f GHz", Double(mhz) / 1000.0)
        } else {
            return "\(mhz) MHz"
        }
    }
}

struct CpuDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let usage: Double
}

struct CircularProgressView: View {
    let progress: Double
    let label: String
    let value: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 10)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var progressColor: Color {
        if progress < 0.5 {
            return .green
        } else if progress < 0.75 {
            return .orange
        } else {
            return .red
        }
    }
}

struct LoadAverageItem: View {
    let label: String
    let value: Double
    let cores: Int
    
    var normalizedValue: Double {
        value / Double(cores)
    }
    
    var color: Color {
        if normalizedValue < 0.7 {
            return .green
        } else if normalizedValue < 1.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(String(format: "%.2f", value))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(color)
            
            Text(String(format: "%.0f%% capacity", normalizedValue * 100))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}