import SwiftUI
import Charts

struct DiskView: View {
    @ObservedObject var rustBridge: RustBridge
    @StateObject private var viewModel: DiskAnalysisViewModel
    @State private var selectedTab = 0
    @State private var scanningPath: String = ""
    @State private var sortColumn: String = "size"
    @State private var sortAscending: Bool = false
    @State private var showError: Bool = false
    @EnvironmentObject var appState: AppState

    init(rustBridge: RustBridge) {
        self.rustBridge = rustBridge
        self._viewModel = StateObject(wrappedValue: DiskAnalysisViewModel(bridge: rustBridge))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Picker("View", selection: $selectedTab) {
                Text("Disks Overview").tag(0)
                Text("Large Files").tag(1)
                Text("Duplicates").tag(2)
                Text("Categories").tag(3)
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
            case 3:
                categoriesTab
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
        VStack(spacing: 0) {
            // Scan controls
            HStack {
                TextField("Enter path to scan (e.g., /Users/YourName/Documents)", text: $scanningPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isScanning)

                Button(viewModel.isScanning ? "Scanning..." : "Scan Directory") {
                    Task {
                        await viewModel.startDirectoryScan(path: scanningPath)
                    }
                }
                .disabled(viewModel.isScanning || scanningPath.isEmpty)

                if viewModel.isScanning {
                    Button("Cancel") {
                        viewModel.cancelScan()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()

            // Progress bar
            if viewModel.isScanning {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.scanProgress, total: 1.0)
                    Text(String(format: "Scanning... %.0f%%", viewModel.scanProgress * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Summary stats
            if !viewModel.largestFiles.isEmpty {
                HStack(spacing: 30) {
                    VStack(alignment: .leading) {
                        Text("Total Size")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(viewModel.totalSize), countStyle: .file))
                            .font(.headline)
                    }

                    VStack(alignment: .leading) {
                        Text("Files Found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.fileCount)")
                            .font(.headline)
                    }

                    VStack(alignment: .leading) {
                        Text("Showing Top")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.largestFiles.count)")
                            .font(.headline)
                    }

                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }

            Divider()

            // Files table
            if viewModel.largestFiles.isEmpty && !viewModel.isScanning {
                VStack(spacing: 12) {
                    Image(systemName: "folder.fill.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No files scanned yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Enter a path above and click 'Scan Directory' to analyze files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedLargestFiles) {
                    TableColumn("Name") { file in
                        HStack {
                            Image(systemName: iconForCategory(file.category))
                                .foregroundColor(colorForCategory(file.category))
                            VStack(alignment: .leading) {
                                Text(file.fileName)
                                    .font(.system(.body, design: .default))
                                Text(file.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 200, ideal: 300)

                    TableColumn("Size") { file in
                        Text(file.sizeFormatted)
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(100)

                    TableColumn("Category") { file in
                        Text(file.category.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(colorForCategory(file.category).opacity(0.2))
                            .cornerRadius(4)
                    }
                    .width(100)

                    TableColumn("Modified") { file in
                        Text(file.modified, style: .relative)
                            .font(.caption)
                    }
                    .width(100)

                    TableColumn("Actions") { file in
                        HStack(spacing: 4) {
                            Button {
                                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")

                            Button {
                                moveToTrash(file.path)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                            .help("Move to Trash")
                        }
                    }
                    .width(80)
                }
            }
        }
        .alert("Scan Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                viewModel.scanError = nil
            }
        } message: {
            Text(viewModel.scanError ?? "Unknown error")
        }
        .onChange(of: viewModel.scanError) { newValue in
            showError = newValue != nil
        }
    }

    var sortedLargestFiles: [FileEntry] {
        viewModel.largestFiles.sorted { file1, file2 in
            switch sortColumn {
            case "size":
                return sortAscending ? file1.size < file2.size : file1.size > file2.size
            case "name":
                return sortAscending ? file1.fileName < file2.fileName : file1.fileName > file2.fileName
            case "modified":
                return sortAscending ? file1.modified < file2.modified : file1.modified > file2.modified
            default:
                return file1.size > file2.size
            }
        }
    }

    var duplicatesTab: some View {
        VStack(spacing: 0) {
            // Scan controls
            HStack {
                TextField("Enter path to search (e.g., /Users/YourName/Documents)", text: $scanningPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isScanning)

                Button(viewModel.isScanning ? "Searching..." : "Find Duplicates") {
                    Task {
                        await viewModel.startDuplicateScan(path: scanningPath)
                    }
                }
                .disabled(viewModel.isScanning || scanningPath.isEmpty)

                if viewModel.isScanning {
                    Button("Cancel") {
                        viewModel.cancelScan()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()

            // Progress bar
            if viewModel.isScanning {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.scanProgress, total: 1.0)
                    Text(String(format: "Searching... %.0f%%", viewModel.scanProgress * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Summary stats
            if !viewModel.duplicates.isEmpty {
                HStack(spacing: 30) {
                    VStack(alignment: .leading) {
                        Text("Duplicate Groups")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.duplicates.count)")
                            .font(.headline)
                    }

                    VStack(alignment: .leading) {
                        Text("Total Files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.duplicates.reduce(0) { $0 + $1.files.count })")
                            .font(.headline)
                    }

                    VStack(alignment: .leading) {
                        Text("Recoverable Space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.totalWastedSpaceFormatted)
                            .font(.headline)
                            .foregroundColor(.orange)
                    }

                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }

            Divider()

            // Duplicates list
            if viewModel.duplicates.isEmpty && !viewModel.isScanning {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No duplicates found yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Enter a path above and click 'Find Duplicates' to search")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.duplicates) { group in
                            DuplicateGroupView(group: group)
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("Scan Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                viewModel.scanError = nil
            }
        } message: {
            Text(viewModel.scanError ?? "Unknown error")
        }
    }

    var categoriesTab: some View {
        VStack(spacing: 0) {
            if let stats = viewModel.categoryStats {
                ScrollView {
                    VStack(spacing: 20) {
                        // Category chart
                        VStack(alignment: .leading, spacing: 12) {
                            Text("File Distribution by Category")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal)

                            if #available(macOS 14.0, *) {
                                Chart {
                                    ForEach(FileCategory.allCases, id: \.self) { category in
                                        let categoryStats = stats.getStats(for: category)
                                        if categoryStats.size > 0 {
                                            SectorMark(
                                                angle: .value("Size", Double(categoryStats.size)),
                                                innerRadius: .ratio(0.5),
                                                angularInset: 2
                                            )
                                            .foregroundStyle(colorForCategory(category))
                                            .cornerRadius(4)
                                        }
                                    }
                                }
                                .frame(height: 300)
                                .chartLegend(position: .trailing) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(FileCategory.allCases, id: \.self) { category in
                                            let categoryStats = stats.getStats(for: category)
                                            if categoryStats.size > 0 {
                                                HStack {
                                                    Circle()
                                                        .fill(colorForCategory(category))
                                                        .frame(width: 12, height: 12)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(category.displayName)
                                                            .font(.caption)
                                                        Text("\(categoryStats.count) files")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Text(ByteCountFormatter.string(fromByteCount: Int64(categoryStats.size), countStyle: .file))
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            } else {
                                // Fallback for older macOS
                                VStack(spacing: 12) {
                                    Text("Charts require macOS 14.0+")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    ForEach(FileCategory.allCases, id: \.self) { category in
                                        let categoryStats = stats.getStats(for: category)
                                        if categoryStats.size > 0 {
                                            CategoryBarView(
                                                category: category,
                                                count: categoryStats.count,
                                                size: categoryStats.size,
                                                totalSize: stats.totalSize,
                                                color: colorForCategory(category)
                                            )
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                        }

                        // Category details table
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Category Statistics")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal)

                            VStack(spacing: 0) {
                                // Header
                                HStack {
                                    Text("Category")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Files")
                                        .font(.headline)
                                        .frame(width: 80, alignment: .trailing)
                                    Text("Size")
                                        .font(.headline)
                                        .frame(width: 120, alignment: .trailing)
                                    Text("% of Total")
                                        .font(.headline)
                                        .frame(width: 100, alignment: .trailing)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))

                                Divider()

                                // Rows
                                ForEach(FileCategory.allCases, id: \.self) { category in
                                    let categoryStats = stats.getStats(for: category)
                                    if categoryStats.size > 0 {
                                        HStack {
                                            HStack {
                                                Image(systemName: iconForCategory(category))
                                                    .foregroundColor(colorForCategory(category))
                                                Text(category.displayName)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            Text("\(categoryStats.count)")
                                                .font(.system(.body, design: .monospaced))
                                                .frame(width: 80, alignment: .trailing)

                                            Text(ByteCountFormatter.string(fromByteCount: Int64(categoryStats.size), countStyle: .file))
                                                .font(.system(.body, design: .monospaced))
                                                .frame(width: 120, alignment: .trailing)

                                            let percentage = stats.totalSize > 0 ? (Double(categoryStats.size) / Double(stats.totalSize)) * 100.0 : 0.0
                                            Text(String(format: "%.1f%%", percentage))
                                                .font(.system(.body, design: .monospaced))
                                                .frame(width: 100, alignment: .trailing)
                                        }
                                        .padding()
                                        .background(Color(NSColor.textBackgroundColor))

                                        Divider()
                                    }
                                }

                                // Total row
                                HStack {
                                    Text("Total")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(stats.totalCount)")
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.bold)
                                        .frame(width: 80, alignment: .trailing)

                                    Text(ByteCountFormatter.string(fromByteCount: Int64(stats.totalSize), countStyle: .file))
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.bold)
                                        .frame(width: 120, alignment: .trailing)

                                    Text("100.0%")
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.bold)
                                        .frame(width: 100, alignment: .trailing)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                            }
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No category data available")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Scan a directory in the 'Large Files' tab first")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    func iconForCategory(_ category: FileCategory) -> String {
        switch category {
        case .documents:
            return "doc.text.fill"
        case .media:
            return "photo.fill"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .archives:
            return "archivebox.fill"
        case .system:
            return "gear.circle.fill"
        case .other:
            return "doc.fill"
        }
    }

    func colorForCategory(_ category: FileCategory) -> Color {
        switch category {
        case .documents:
            return .blue
        case .media:
            return .purple
        case .code:
            return .green
        case .archives:
            return .orange
        case .system:
            return .gray
        case .other:
            return .secondary
        }
    }

    func moveToTrash(_ path: String) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            print("Error moving to trash: \(error)")
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

// MARK: - Duplicate Group View
struct DuplicateGroupView: View {
    let group: DuplicateGroup
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(group.files.count) copies")
                            .font(.headline)
                        Text("\(group.duplicateCount) duplicate\(group.duplicateCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Wasted: \(group.wastedSpaceFormatted)")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        Text("Size: \(group.totalSizeFormatted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        deleteAllDuplicates()
                    } label: {
                        Label("Delete Duplicates", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .help("Keep first file, delete all duplicates")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Expanded file list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                        HStack {
                            if index == 0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .help("Original file (will be kept)")
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.orange)
                                    .help("Duplicate file")
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.fileName)
                                    .font(.subheadline)
                                Text(file.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button {
                                    NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")

                                if index != 0 {
                                    Button {
                                        moveToTrash(file.path)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.red)
                                    .help("Move to Trash")
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
    }

    private func deleteAllDuplicates() {
        // Keep first file, delete rest
        for file in group.files.dropFirst() {
            moveToTrash(file.path)
        }
    }

    private func moveToTrash(_ path: String) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            print("Error moving to trash: \(error)")
        }
    }
}

// MARK: - Category Bar View (Fallback)
struct CategoryBarView: View {
    let category: FileCategory
    let count: Int
    let size: UInt64
    let totalSize: UInt64
    let color: Color

    var percentage: Double {
        totalSize > 0 ? (Double(size) / Double(totalSize)) * 100.0 : 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                    Text(category.displayName)
                        .font(.subheadline)
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption)
                    .fontWeight(.medium)

                Text(String(format: "%.1f%%", percentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage / 100.0), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}
