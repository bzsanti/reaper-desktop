import SwiftUI
import Charts

struct DiskView: View {
    @ObservedObject var rustBridge: RustBridge
    @State private var selectedTab = 0
    @State private var scanningPath: String = ""
    @State private var isScanning = false
    @State private var scanProgress: Double = 0.0
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Picker("View", selection: $selectedTab) {
                Text("Disks Overview").tag(0)
                Text("Large Files").tag(1)
                Text("Duplicates").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case 0:
                disksOverviewTab
            case 1:
                largeFilesTab
            case 2:
                duplicatesTab
            default:
                EmptyView()
            }
        }
    }

    var headerView: some View {
        VStack(spacing: 12) {
            if let primary = rustBridge.primaryDisk {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Primary Disk")
                            .font(.headline)
                        Text(primary.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(primary.mountPoint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Capacity")
                            .font(.headline)
                        Text(formatBytes(primary.totalBytes))
                            .font(.title3)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available")
                            .font(.headline)
                        Text(formatBytes(primary.availableBytes))
                            .font(.title3)
                            .foregroundColor(colorForUsage(primary.usagePercent))
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Usage")
                            .font(.headline)
                        Text(String(format: "%.1f%%", primary.usagePercent))
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(colorForUsage(primary.usagePercent))
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
    }

    var disksOverviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // All disks list
                if !rustBridge.allDisks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("All Mounted Disks")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        ForEach(rustBridge.allDisks) { disk in
                            diskCard(disk)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }

                // Disk usage chart
                if let primary = rustBridge.primaryDisk {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Disk Usage Breakdown")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        diskUsageChart(primary)
                            .frame(height: 300)
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    var largeFilesTab: some View {
        VStack {
            HStack {
                TextField("Enter path to scan (e.g., /Users)", text: $scanningPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isScanning)

                Button(isScanning ? "Scanning..." : "Scan Directory") {
                    startDirectoryScan()
                }
                .disabled(isScanning || scanningPath.isEmpty)
            }
            .padding()

            if isScanning {
                ProgressView(value: scanProgress, total: 1.0)
                    .padding()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Feature Coming Soon")
                        .font(.title2)
                        .padding()
                    Text("This feature will show:")
                        .font(.headline)
                        .padding(.horizontal)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Largest files in the selected directory", systemImage: "doc.fill")
                        Label("Directory size analysis", systemImage: "folder.fill")
                        Label("Space usage by file type", systemImage: "chart.pie.fill")
                        Label("Quick actions to free up space", systemImage: "trash.fill")
                    }
                    .padding()
                }
            }
        }
    }

    var duplicatesTab: some View {
        VStack {
            HStack {
                TextField("Enter path to search (e.g., /Users)", text: $scanningPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isScanning)

                Button(isScanning ? "Searching..." : "Find Duplicates") {
                    startDuplicateScan()
                }
                .disabled(isScanning || scanningPath.isEmpty)
            }
            .padding()

            if isScanning {
                ProgressView(value: scanProgress, total: 1.0)
                    .padding()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Feature Coming Soon")
                        .font(.title2)
                        .padding()
                    Text("This feature will find:")
                        .font(.headline)
                        .padding(.horizontal)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Duplicate files by content (hash-based)", systemImage: "doc.on.doc.fill")
                        Label("Similar files by name", systemImage: "magnifyingglass")
                        Label("Estimated space savings", systemImage: "arrow.down.circle.fill")
                        Label("Safe deletion options", systemImage: "trash.fill")
                    }
                    .padding()
                }
            }
        }
    }

    func diskCard(_ disk: DiskMetrics) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: iconForDiskType(disk.diskType))
                            .foregroundColor(.blue)
                        Text(disk.name)
                            .font(.headline)
                        if disk.isRemovable {
                            Image(systemName: "eject.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Text(disk.mountPoint)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(disk.fileSystem) • \(disk.diskType)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatBytes(disk.availableBytes) + " available")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(formatBytes(disk.totalBytes) + " total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            // Usage bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    Rectangle()
                        .fill(colorForUsage(disk.usagePercent))
                        .frame(width: geometry.size.width * CGFloat(disk.usagePercent / 100.0), height: 8)
                }
            }
            .frame(height: 8)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Text(String(format: "%.1f%% used (%@ of %@)",
                       disk.usagePercent,
                       formatBytes(disk.usedBytes),
                       formatBytes(disk.totalBytes)))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    func diskUsageChart(_ disk: DiskMetrics) -> some View {
        if #available(macOS 14.0, *) {
            Chart {
                SectorMark(
                    angle: .value("Used", Double(disk.usedBytes)),
                    innerRadius: .ratio(0.6),
                    angularInset: 2
                )
                .foregroundStyle(colorForUsage(disk.usagePercent))
                .annotation(position: .overlay) {
                    VStack {
                        Text(String(format: "%.1f%%", disk.usagePercent))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Used")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                SectorMark(
                    angle: .value("Available", Double(disk.availableBytes)),
                    innerRadius: .ratio(0.6),
                    angularInset: 2
                )
                .foregroundStyle(.green.opacity(0.3))
            }
            .chartLegend(position: .bottom) {
                HStack(spacing: 20) {
                    HStack {
                        Circle()
                            .fill(colorForUsage(disk.usagePercent))
                            .frame(width: 12, height: 12)
                        Text("Used: \(formatBytes(disk.usedBytes))")
                            .font(.caption)
                    }

                    HStack {
                        Circle()
                            .fill(.green.opacity(0.3))
                            .frame(width: 12, height: 12)
                        Text("Available: \(formatBytes(disk.availableBytes))")
                            .font(.caption)
                    }
                }
            }
        } else {
            // Fallback for older macOS versions
            VStack {
                Text("Chart requires macOS 14.0+")
                    .foregroundColor(.secondary)

                HStack(spacing: 20) {
                    VStack {
                        Circle()
                            .fill(colorForUsage(disk.usagePercent))
                            .frame(width: 60, height: 60)
                        Text("Used: \(formatBytes(disk.usedBytes))")
                            .font(.caption)
                    }

                    VStack {
                        Circle()
                            .fill(.green.opacity(0.3))
                            .frame(width: 60, height: 60)
                        Text("Available: \(formatBytes(disk.availableBytes))")
                            .font(.caption)
                    }
                }
            }
        }
    }

    func iconForDiskType(_ type: String) -> String {
        switch type.lowercased() {
        case "ssd":
            return "internaldrive.fill"
        case "hdd":
            return "externaldrive.fill"
        case "network":
            return "server.rack"
        case "removable":
            return "externaldrive.badge.plus"
        default:
            return "internaldrive"
        }
    }

    func startDirectoryScan() {
        isScanning = true
        scanProgress = 0.0

        // Simulate scanning for now
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            scanProgress += 0.05
            if scanProgress >= 1.0 {
                timer.invalidate()
                isScanning = false
                // TODO: Implement actual directory scanning
            }
        }
    }

    func startDuplicateScan() {
        isScanning = true
        scanProgress = 0.0

        // Simulate scanning for now
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            scanProgress += 0.05
            if scanProgress >= 1.0 {
                timer.invalidate()
                isScanning = false
                // TODO: Implement actual duplicate detection
            }
        }
    }

    func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024.0 && unitIndex < units.count - 1 {
            size /= 1024.0
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        } else {
            return String(format: "%.1f %@", size, units[unitIndex])
        }
    }

    func colorForUsage(_ usage: Float) -> Color {
        switch usage {
        case 0..<70:
            return .green
        case 70..<85:
            return .orange
        default:
            return .red
        }
    }
}
