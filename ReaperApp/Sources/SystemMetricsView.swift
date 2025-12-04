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
                    
                    cpuLimitedProcessesCard()
                    
                    if let hardware = rustBridge.hardwareMetrics {
                        hardwareMetricsCard(hardware)
                    }
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
    
    func hardwareMetricsCard(_ hardware: HardwareMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hardware Sensors")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Thermal state indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(hardware.thermalState.color)
                        .frame(width: 8, height: 8)
                    Text(hardware.thermalState.description)
                        .font(.caption)
                        .foregroundColor(hardware.thermalState.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(hardware.thermalState.color.opacity(0.1))
                .cornerRadius(6)
            }
            
            // CPU Frequency
            if hardware.cpuFrequencyMHz > 0 {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(.blue)
                    Text("CPU Frequency")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f GHz", hardware.cpuFrequencyGHz))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
            
            // Temperature Sensors
            if !hardware.temperatures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temperature Sensors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    ForEach(hardware.temperatures) { sensor in
                        HStack {
                            Image(systemName: sensor.sensorType.icon)
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            
                            Text(sensor.name)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            // Temperature value with color coding
                            Text(String(format: "%.1f°C", sensor.valueCelsius))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(temperatureColor(sensor.valueCelsius))
                            
                            if sensor.isCritical {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 8)
            }
            
            // Power Metrics (if available)
            if hardware.cpuPowerWatts != nil || hardware.gpuPowerWatts != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Power Consumption")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    if let cpuPower = hardware.cpuPowerWatts {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text("CPU Power")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f W", cpuPower))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }
                    
                    if let gpuPower = hardware.gpuPowerWatts {
                        HStack {
                            Image(systemName: "gpu.card")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text("GPU Power")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f W", gpuPower))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }
                    
                    if let totalPower = hardware.totalPowerWatts {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                                .frame(width: 20)
                            Text("Total Power")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f W", totalPower))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    func temperatureColor(_ celsius: Float) -> Color {
        switch celsius {
        case ..<50:
            return .green
        case 50..<65:
            return .yellow
        case 65..<80:
            return .orange
        default:
            return .red
        }
    }
    
    func cpuLimitedProcessesCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CPU Limited Processes")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !rustBridge.cpuLimitedProcesses.isEmpty {
                    Text("\(rustBridge.cpuLimitedProcesses.count) active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            
            if rustBridge.cpuLimitedProcesses.isEmpty {
                HStack {
                    Image(systemName: "gauge.badge.minus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No processes have CPU limits")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(rustBridge.cpuLimitedProcesses) { limitInfo in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    // Try to get process name from current processes
                                    if let process = rustBridge.processes.first(where: { $0.pid == limitInfo.pid }) {
                                        Text(process.name)
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.medium)
                                    } else {
                                        Text("PID \(limitInfo.pid)")
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.medium)
                                    }
                                    
                                    Text("• \(limitInfo.limitType.description)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(spacing: 12) {
                                    Label("\(Int(limitInfo.maxCpuPercent))% max", systemImage: "speedometer")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    
                                    if limitInfo.niceValue != 0 {
                                        Label("Nice: \(limitInfo.niceValue)", systemImage: "arrow.down.circle")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                _ = rustBridge.removeProcessLimit(limitInfo.pid)
                            }) {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove CPU limit")
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
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