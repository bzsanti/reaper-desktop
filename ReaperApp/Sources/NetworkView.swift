import SwiftUI
import Foundation

struct NetworkView: View {
    @ObservedObject var rustBridge: RustBridge
    @State private var selectedConnection: NetworkConnection?
    @State private var searchText = ""
    @State private var selectedProtocol = "All"
    @State private var selectedState = "All"
    @State private var showActiveOnly = false
    
    private let protocols = ["All", "TCP", "UDP", "TCP6", "UDP6"]
    private let states = ["All", "Established", "Listen", "SYN Sent", "SYN Received", 
                         "FIN Wait 1", "FIN Wait 2", "Time Wait", "Close Wait", "Closed"]
    
    var filteredConnections: [NetworkConnection] {
        guard let networkMetrics = rustBridge.networkMetrics else { return [] }
        
        return networkMetrics.connections.filter { connection in
            // Search filter
            let matchesSearch = searchText.isEmpty || 
                connection.processName.localizedCaseInsensitiveContains(searchText) ||
                connection.localAddress.contains(searchText) ||
                connection.remoteAddress.contains(searchText) ||
                "\(connection.localPort)".contains(searchText) ||
                "\(connection.remotePort)".contains(searchText)
            
            // Protocol filter
            let matchesProtocol = selectedProtocol == "All" || 
                connection.networkProtocol.uppercased() == selectedProtocol.uppercased()
            
            // State filter
            let matchesState = selectedState == "All" || 
                connection.state.localizedCaseInsensitiveContains(selectedState)
            
            // Active filter
            let matchesActive = !showActiveOnly || 
                connection.state.localizedCaseInsensitiveContains("established")
            
            return matchesSearch && matchesProtocol && matchesState && matchesActive
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with bandwidth stats
            bandwidthStatsHeader
            
            // Filters
            filterControls
            
            // Connections table
            Group {
                if rustBridge.networkMetrics != nil {
                    if filteredConnections.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "network")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            VStack(spacing: 4) {
                                Text("No Network Connections")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                Text("No connections match the current filters")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        connectionsTable
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        VStack(spacing: 4) {
                            Text("Loading Network Data")
                                .font(.title2)
                                .fontWeight(.medium)
                            Text("Gathering network connection information...")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var bandwidthStatsHeader: some View {
        VStack(spacing: 8) {
            if let networkMetrics = rustBridge.networkMetrics {
                HStack(spacing: 20) {
                    bandwidthCard(
                        title: "Download",
                        current: formatBandwidth(networkMetrics.bandwidth.currentDownloadBps),
                        peak: formatBandwidth(networkMetrics.bandwidth.peakDownloadBps),
                        average: formatBandwidth(networkMetrics.bandwidth.averageDownloadBps),
                        color: .blue
                    )
                    
                    bandwidthCard(
                        title: "Upload", 
                        current: formatBandwidth(networkMetrics.bandwidth.currentUploadBps),
                        peak: formatBandwidth(networkMetrics.bandwidth.peakUploadBps),
                        average: formatBandwidth(networkMetrics.bandwidth.averageUploadBps),
                        color: .green
                    )
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total Data")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("↓ \(formatBytes(networkMetrics.totalBytesReceived))")
                                .foregroundColor(.blue)
                            Text("↑ \(formatBytes(networkMetrics.totalBytesSent))")
                                .foregroundColor(.green)
                        }
                        .font(.system(.body, design: .monospaced))
                        
                        Text("\(networkMetrics.packetsSent + networkMetrics.packetsReceived) packets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }
    
    private func bandwidthCard(title: String, current: String, peak: String, average: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Current:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(current)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Peak:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(peak)
                        .font(.system(.caption2, design: .monospaced))
                }
                
                HStack {
                    Text("Average:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(average)
                        .font(.system(.caption2, design: .monospaced))
                }
            }
        }
        .frame(width: 140)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var filterControls: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search connections...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .frame(width: 200)
            
            // Protocol filter
            Picker("Protocol", selection: $selectedProtocol) {
                ForEach(protocols, id: \.self) { protocolName in
                    Text(protocolName).tag(protocolName)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 80)
            
            // State filter
            Picker("State", selection: $selectedState) {
                ForEach(states, id: \.self) { state in
                    Text(state).tag(state)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 120)
            
            // Active only toggle
            Toggle("Active Only", isOn: $showActiveOnly)
                .toggleStyle(CheckboxToggleStyle())
            
            Spacer()
            
            // Connection count
            Text("\(filteredConnections.count) connections")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var connectionsTable: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                // Header
                connectionTableHeader
                
                // Connections
                ForEach(filteredConnections) { connection in
                    connectionRow(connection)
                        .background(
                            selectedConnection?.id == connection.id ? 
                            Color.accentColor.opacity(0.2) : 
                            Color(NSColor.controlBackgroundColor)
                        )
                        .onTapGesture {
                            selectedConnection = connection
                        }
                }
            }
        }
    }
    
    private var connectionTableHeader: some View {
        HStack(spacing: 8) {
            Text("Process")
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .leading)
            
            Text("Protocol")
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            
            Text("Local Address:Port")
                .fontWeight(.semibold)
                .frame(width: 160, alignment: .leading)
            
            Text("Remote Address:Port")
                .fontWeight(.semibold)
                .frame(width: 160, alignment: .leading)
            
            Text("State")
                .fontWeight(.semibold)
                .frame(width: 100, alignment: .leading)
            
            Text("Data")
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.separatorColor).opacity(0.2))
        .font(.system(.caption, design: .default))
        .foregroundColor(.secondary)
    }
    
    private func connectionRow(_ connection: NetworkConnection) -> some View {
        HStack(spacing: 8) {
            // Process name
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.processName.isEmpty ? "Unknown" : connection.processName)
                    .font(.system(.caption, design: .default))
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let pid = connection.pid {
                    Text("PID: \(pid)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, alignment: .leading)
            
            // Protocol
            Text(connection.networkProtocol)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 60, alignment: .leading)
            
            // Local address
            Text("\(connection.localAddress):\(connection.localPort)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 160, alignment: .leading)
            
            // Remote address
            Text(connection.remoteAddress.isEmpty || connection.remoteAddress == "*" ? 
                 "*" : "\(connection.remoteAddress):\(connection.remotePort)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 160, alignment: .leading)
            
            // State
            HStack(spacing: 4) {
                Circle()
                    .fill(connection.stateColor)
                    .frame(width: 6, height: 6)
                Text(connection.state)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(width: 100, alignment: .leading)
            
            // Data transferred
            VStack(alignment: .trailing, spacing: 1) {
                if connection.bytesSent > 0 || connection.bytesReceived > 0 {
                    Text("↑ \(formatBytes(connection.bytesSent))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.green)
                    Text("↓ \(formatBytes(connection.bytesReceived))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.blue)
                } else {
                    Text("-")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    private func formatBandwidth(_ bps: UInt64) -> String {
        let bytes = Double(bps)
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB/s", bytes / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            return String(format: "%.1f MB/s", bytes / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.1f KB/s", bytes / 1_000)
        } else {
            return String(format: "%.0f B/s", bytes)
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let size = Double(bytes)
        if size >= 1_073_741_824 {
            return String(format: "%.1f GB", size / 1_073_741_824)
        } else if size >= 1_048_576 {
            return String(format: "%.1f MB", size / 1_048_576)
        } else if size >= 1_024 {
            return String(format: "%.1f KB", size / 1_024)
        } else {
            return String(format: "%.0f B", size)
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                    .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                configuration.label
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NetworkView(rustBridge: RustBridge())
        .frame(width: 900, height: 600)
}