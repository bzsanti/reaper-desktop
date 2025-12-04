import SwiftUI

struct ContentView: View {
    @StateObject private var rustBridge = RustBridge()
    @State private var selectedTab = 0
    @State private var selectedProcess: ProcessInfo?
    @State private var showingDetails = false
    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject var appState: AppState
    
    // Version info
    private let appVersion = "0.4.7"  // Disk module expansion - Phase 1
    private let buildVersion = "20251204225923"  // Unique build timestamp
    private let buildTimestamp = Date()
    
    var body: some View {
        HSplitView {
            // Main content area
            VStack(spacing: 0) {
                headerView
                
                TabView(selection: $selectedTab) {
                    if #available(macOS 14.4, *) {
                        ProcessListView(
                            rustBridge: rustBridge,
                            searchText: $appState.searchText,
                            selectedProcess: $selectedProcess,
                            showingDetails: $showingDetails
                        )
                        .tabItem {
                            Label("All Processes", systemImage: "list.bullet")
                        }
                        .tag(0)
                    } else {
                        Text("This feature requires macOS 14.4 or later")
                            .tabItem {
                                Label("All Processes", systemImage: "list.bullet")
                            }
                            .tag(0)
                    }
                    
                    HighCpuView(rustBridge: rustBridge)
                        .tabItem {
                            Label("High CPU", systemImage: "flame")
                        }
                        .tag(1)
                    
                    MemoryView(rustBridge: rustBridge)
                        .tabItem {
                            Label("Memory", systemImage: "memorychip")
                        }
                        .tag(2)
                    
                    NetworkView(rustBridge: rustBridge)
                        .tabItem {
                            Label("Network", systemImage: "network")
                        }
                        .tag(3)

                    DiskView(rustBridge: rustBridge)
                        .tabItem {
                            Label("Disk", systemImage: "internaldrive")
                        }
                        .tag(4)

                    SystemMetricsView(rustBridge: rustBridge)
                        .tabItem {
                            Label("System Metrics", systemImage: "speedometer")
                        }
                        .tag(5)

                    // Advanced CPU Analysis Tab (v0.4.6)
                    VStack {
                        HStack {
                            ThermalMonitorView(rustBridge: rustBridge)
                            Divider()
                            CpuHistoryView(rustBridge: rustBridge)
                        }
                    }
                    .tabItem {
                        Label("Advanced CPU", systemImage: "cpu")
                    }
                    .tag(6)
                }
            }
            .frame(minWidth: 600)
            
            // Details panel (conditional)
            if showingDetails {
                if let process = selectedProcess {
                    ProcessDetailView(process: process, rustBridge: rustBridge)
                        .id(process.pid) // Force view recreation when process changes
                        .transition(.move(edge: .trailing))
                } else {
                    // Empty state when no process is selected
                    VStack {
                        Spacer()
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Select a Process")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Click on a process to see its details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                    .background(Color(NSColor.controlBackgroundColor))
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: appState.shouldShowDetails) { shouldShow in
            if shouldShow {
                showingDetails = true
                appState.shouldShowDetails = false
            }
        }
        .onChange(of: appState.isSearchFieldFocused) { shouldFocus in
            print("🔍 Search focus changed: \(shouldFocus)")
            if shouldFocus {
                print("🎯 Setting search field focus to true")
                isSearchFocused = true
                // Reset the flag after using it
                DispatchQueue.main.async {
                    appState.isSearchFieldFocused = false
                    print("✅ Reset search focus flag")
                }
            }
        }
    }
    
    var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reaper")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("v\(appVersion) • Build \(buildVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    if let metrics = rustBridge.cpuMetrics {
                        MetricBadge(
                            label: "CPU",
                            value: String(format: "%.1f%%", metrics.totalUsage),
                            color: colorForCpuUsage(metrics.totalUsage)
                        )

                        // CPU Temperature Badge
                        // Prefer XPC temperature for consistency with MenuBar when available
                        if let xpcTemp = rustBridge.xpcTemperature {
                            MetricBadge(
                                label: "Temp",
                                value: String(format: "%.0f°C", xpcTemp),
                                color: colorForTemperature(xpcTemp)
                            )
                        } else if let hardware = rustBridge.hardwareMetrics,
                           let cpuTemp = hardware.temperatures.first(where: { $0.sensorType == .cpuPackage || $0.sensorType == .cpuCore }) {
                            // Fallback to hardware sensors when XPC is not available
                            MetricBadge(
                                label: "Temp",
                                value: String(format: "%.0f°C", cpuTemp.valueCelsius),
                                color: colorForTemperature(cpuTemp.valueCelsius)
                            )
                        }

                        MetricBadge(
                            label: "Load",
                            value: String(format: "%.2f", metrics.loadAverage1),
                            color: .blue
                        )

                        MetricBadge(
                            label: "Cores",
                            value: "\(metrics.coreCount)",
                            color: .purple
                        )
                    }
                    
                    if let disk = rustBridge.primaryDisk {
                        MetricBadge(
                            label: "Disk",
                            value: disk.formatBytes(disk.availableBytes),
                            color: colorForDiskUsage(disk.usagePercent)
                        )
                    }
                }
                
                // Details toggle button
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingDetails.toggle()
                    }
                }) {
                    Image(systemName: showingDetails ? "sidebar.right" : "sidebar.left")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("i", modifiers: .command)
                .help("Toggle Details Panel (⌘I)")
                
                Button(action: { rustBridge.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            if selectedTab == 0 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search processes...", text: $appState.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    
                    if !appState.searchText.isEmpty {
                        Button(action: { appState.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    func colorForCpuUsage(_ usage: Float) -> Color {
        switch usage {
        case 0..<50:
            return .green
        case 50..<75:
            return .orange
        default:
            return .red
        }
    }
    
    func colorForDiskUsage(_ usagePercent: Float) -> Color {
        switch usagePercent {
        case 0..<70:
            return .green
        case 70..<90:
            return .orange
        default:
            return .red
        }
    }

    func colorForTemperature(_ temp: Float) -> Color {
        switch temp {
        case 0..<50:
            return .green
        case 50..<70:
            return .yellow
        case 70..<85:
            return .orange
        default:
            return .red
        }
    }
}

struct MetricBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}