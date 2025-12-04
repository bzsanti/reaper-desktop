import SwiftUI

struct ContentView: View {
    @StateObject private var rustBridge = RustBridge()
    @State private var selectedTab = 0
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            TabView(selection: $selectedTab) {
                ProcessListView(rustBridge: rustBridge, searchText: $searchText)
                    .tabItem {
                        Label("All Processes", systemImage: "list.bullet")
                    }
                    .tag(0)
                
                HighCpuView(rustBridge: rustBridge)
                    .tabItem {
                        Label("High CPU", systemImage: "flame")
                    }
                    .tag(1)
                
                SystemMetricsView(rustBridge: rustBridge)
                    .tabItem {
                        Label("System Metrics", systemImage: "speedometer")
                    }
                    .tag(2)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("CPU Monitor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let metrics = rustBridge.cpuMetrics {
                    HStack(spacing: 20) {
                        MetricBadge(
                            label: "CPU",
                            value: String(format: "%.1f%%", metrics.totalUsage),
                            color: colorForCpuUsage(metrics.totalUsage)
                        )
                        
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
                }
                
                Button(action: { rustBridge.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            if selectedTab == 0 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search processes...", text: $searchText)
                        .textFieldStyle(.plain)
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