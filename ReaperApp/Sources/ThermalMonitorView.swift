import SwiftUI
import Charts

// MARK: - Thermal Data Structures

struct ThermalSensor: Identifiable {
    let id = UUID()
    let name: String
    let location: String
    let currentTemperature: Float
    let maxTemperature: Float
    let isThrottling: Bool
    
    var temperatureColor: Color {
        if currentTemperature > 85 {
            return .red
        } else if currentTemperature > 70 {
            return .orange
        } else if currentTemperature > 50 {
            return .yellow
        } else {
            return .green
        }
    }
}

struct ThermalData {
    let sensors: [ThermalSensor]
    let cpuTemperature: Float
    let isThrottling: Bool
    let hottestTemperature: Float
}

// MARK: - CPU History Data

struct CpuHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let cpuUsage: Float
    let frequencyMHz: UInt64
    let temperature: Float
}

struct CpuHistoryData {
    let points: [CpuHistoryPoint]
    let averageUsage: Float
    let maxUsage: Float
    let minUsage: Float
}

// MARK: - Thermal Monitor View

struct ThermalMonitorView: View {
    @ObservedObject var rustBridge: RustBridge
    @State private var thermalData: ThermalData?
    @State private var temperatureHistory: [Double] = []
    @State private var refreshTimer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection
                
                // CPU Temperature Card
                if let thermal = thermalData {
                    cpuTemperatureCard(thermal)
                    
                    // Thermal Throttling Status
                    throttlingStatusCard(thermal)
                    
                    // Sensor Grid
                    sensorGridSection(thermal)
                    
                    // Temperature History Chart
                    if !temperatureHistory.isEmpty {
                        temperatureChartSection
                    }
                }
            }
            .padding()
        }
        .onAppear {
            initializeThermalMonitoring()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }
    
    // MARK: - View Components
    
    var headerSection: some View {
        HStack {
            Image(systemName: "thermometer.medium")
                .font(.title2)
                .foregroundColor(.orange)
            
            Text("Thermal Monitor")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            if thermalData?.isThrottling == true {
                Label("Throttling Active", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }
    
    func cpuTemperatureCard(_ thermal: ThermalData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU Temperature")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .bottom, spacing: 4) {
                Text(String(format: "%.1f", thermal.cpuTemperature))
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .foregroundColor(colorForTemperature(thermal.cpuTemperature))
                
                Text("°C")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Label(String(format: "Max: %.1f°C", thermal.hottestTemperature), 
                          systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if thermal.isThrottling {
                        Label("Performance Limited", systemImage: "tortoise.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Temperature gauge
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * CGFloat(min(thermal.cpuTemperature / 100, 1.0)), 
                               height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    func throttlingStatusCard(_ thermal: ThermalData) -> some View {
        HStack {
            Image(systemName: thermal.isThrottling ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(thermal.isThrottling ? .orange : .green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Thermal Status")
                    .font(.headline)
                
                Text(thermal.isThrottling ? "CPU frequency reduced due to heat" : "Operating normally")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    func sensorGridSection(_ thermal: ThermalData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Temperature Sensors")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(thermal.sensors) { sensor in
                    sensorCard(sensor)
                }
            }
        }
    }
    
    func sensorCard(_ sensor: ThermalSensor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForSensorLocation(sensor.location))
                    .foregroundColor(sensor.temperatureColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sensor.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(sensor.location)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack {
                Text(String(format: "%.1f°C", sensor.currentTemperature))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(sensor.temperatureColor)
                
                Spacer()
                
                Text(String(format: "Max: %.1f°C", sensor.maxTemperature))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    var temperatureChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Temperature History")
                .font(.headline)
            
            Chart(Array(temperatureHistory.enumerated()), id: \.offset) { index, temp in
                LineMark(
                    x: .value("Time", index),
                    y: .value("Temperature", temp)
                )
                .foregroundStyle(.orange)
                
                AreaMark(
                    x: .value("Time", index),
                    y: .value("Temperature", temp)
                )
                .foregroundStyle(.linearGradient(
                    colors: [.orange.opacity(0.3), .orange.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            .frame(height: 150)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Helper Functions
    
    func initializeThermalMonitoring() {
        rustBridge.initializeThermalMonitor()
        refreshThermalData()
    }
    
    func refreshThermalData() {
        if let data = rustBridge.getThermalData() {
            thermalData = data
            
            // Update temperature history
            temperatureHistory.append(Double(data.cpuTemperature))
            if temperatureHistory.count > 60 {
                temperatureHistory.removeFirst()
            }
        }
    }
    
    func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            refreshThermalData()
        }
    }
    
    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func colorForTemperature(_ temp: Float) -> Color {
        switch temp {
        case ..<50: return .green
        case 50..<70: return .yellow
        case 70..<85: return .orange
        default: return .red
        }
    }
    
    func iconForSensorLocation(_ location: String) -> String {
        if location.contains("CPU") || location.contains("Core") {
            return "cpu"
        } else if location.contains("GPU") {
            return "rectangle.3.group.fill"
        } else if location.contains("Memory") {
            return "memorychip"
        } else if location.contains("Battery") {
            return "battery.100"
        } else if location.contains("Ambient") {
            return "thermometer"
        } else {
            return "sensor.fill"
        }
    }
}

// MARK: - CPU History View

struct CpuHistoryView: View {
    @ObservedObject var rustBridge: RustBridge
    @State private var historyData: CpuHistoryData?
    @State private var selectedTimeRange = 5 // minutes
    @State private var isHighFrequencySampling = false
    
    let timeRanges = [1, 5, 15, 30, 60]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with controls
                headerSection
                
                // Statistics cards
                if let history = historyData {
                    statisticsSection(history)
                    
                    // CPU Usage Chart
                    cpuUsageChart(history)
                    
                    // Frequency Chart
                    frequencyChart(history)
                }
            }
            .padding()
        }
        .onAppear {
            rustBridge.initializeCpuHistory()
            refreshHistoryData()
        }
    }
    
    var headerSection: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundColor(.blue)
            
            Text("CPU History")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            // Time range picker
            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(timeRanges, id: \.self) { minutes in
                    Text("\(minutes)m").tag(minutes)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 200)
            .onChange(of: selectedTimeRange) { _ in
                refreshHistoryData()
            }
            
            // High frequency sampling toggle
            Toggle("High Frequency", isOn: $isHighFrequencySampling)
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: isHighFrequencySampling) { enabled in
                    rustBridge.setHighFrequencySampling(enabled)
                }
        }
    }
    
    func statisticsSection(_ history: CpuHistoryData) -> some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Average",
                value: String(format: "%.1f%%", history.averageUsage),
                icon: "chart.bar.fill",
                color: .blue
            )
            
            StatCard(
                title: "Maximum",
                value: String(format: "%.1f%%", history.maxUsage),
                icon: "arrow.up.circle.fill",
                color: .red
            )
            
            StatCard(
                title: "Minimum",
                value: String(format: "%.1f%%", history.minUsage),
                icon: "arrow.down.circle.fill",
                color: .green
            )
            
            StatCard(
                title: "Samples",
                value: "\(history.points.count)",
                icon: "number.circle.fill",
                color: .purple
            )
        }
    }
    
    func cpuUsageChart(_ history: CpuHistoryData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU Usage Over Time")
                .font(.headline)
            
            Chart(history.points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU %", point.cpuUsage)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU %", point.cpuUsage)
                )
                .foregroundStyle(.linearGradient(
                    colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            .frame(height: 200)
            .chartYScale(domain: 0...100)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    func frequencyChart(_ history: CpuHistoryData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU Frequency")
                .font(.headline)
            
            Chart(history.points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("MHz", point.frequencyMHz)
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 150)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    func refreshHistoryData() {
        historyData = rustBridge.getCpuHistory(minutes: UInt32(selectedTimeRange))
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}