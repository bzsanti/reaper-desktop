import SwiftUI

// MARK: - App State

class AppState: ObservableObject {
    // Process selection
    @Published var selectedProcess: ProcessInfo?
    @Published var selectedProcesses = Set<UInt32>()
    
    // UI state
    @Published var shouldShowDetails = false
    @Published var isSearchFieldFocused = false
    @Published var searchText = ""
    
    // Confirmation dialogs
    @Published var showTerminateConfirmation = false
    @Published var showForceKillConfirmation = false
    @Published var processToAct: ProcessInfo?
    
    // Preferences (will be persisted)
    @Published var columnWidths: [String: CGFloat] = [
        "pid": 60,
        "name": 250,
        "cpu": 100,
        "memory": 120,
        "status": 100,
        "threads": 80,
        "runtime": 100,
        "parent_pid": 80,
        "user_time": 80,
        "system_time": 80
    ]
    
    // Column order for reordering functionality
    @Published var columnOrder: [String] = [
        "pid", "name", "cpu", "memory", "status", "threads", 
        "runtime", "parent_pid", "user_time", "system_time"
    ]
    
    @Published var sortOrder = [KeyPathComparator(\ProcessInfo.cpuUsage, order: .reverse)]
    @Published var showDetailsPanel = false
    
    // High CPU settings
    @Published var highCpuThreshold: Float = 25.0
    @Published var groupProcessesByApp = false
    @Published var showCpuTrendChart = true
    
    init() {
        loadPreferences()
    }
    
    // MARK: - Preferences
    
    private func loadPreferences() {
        // Load from UserDefaults
        if let widths = UserDefaults.standard.dictionary(forKey: "columnWidths") as? [String: CGFloat] {
            columnWidths = widths
        }
        
        // Load column order
        if let order = UserDefaults.standard.array(forKey: "columnOrder") as? [String], !order.isEmpty {
            columnOrder = order
        }
        
        showDetailsPanel = UserDefaults.standard.bool(forKey: "showDetailsPanel")
        
        // Load sort preferences if available
        if let sortField = UserDefaults.standard.string(forKey: "sortField"),
           let sortAscending = UserDefaults.standard.object(forKey: "sortAscending") as? Bool {
            // Apply saved sort order
            applySortOrder(field: sortField, ascending: sortAscending)
        }
        
        // Load High CPU settings
        if UserDefaults.standard.object(forKey: "highCpuThreshold") != nil {
            highCpuThreshold = UserDefaults.standard.float(forKey: "highCpuThreshold")
        }
        groupProcessesByApp = UserDefaults.standard.bool(forKey: "groupProcessesByApp")
        if UserDefaults.standard.object(forKey: "showCpuTrendChart") != nil {
            showCpuTrendChart = UserDefaults.standard.bool(forKey: "showCpuTrendChart")
        }
    }
    
    func savePreferences() {
        UserDefaults.standard.set(columnWidths, forKey: "columnWidths")
        UserDefaults.standard.set(columnOrder, forKey: "columnOrder")
        UserDefaults.standard.set(showDetailsPanel, forKey: "showDetailsPanel")
        
        // Save sort preferences
        if let firstSort = sortOrder.first {
            let field = getSortFieldName(from: firstSort)
            UserDefaults.standard.set(field, forKey: "sortField")
            UserDefaults.standard.set(firstSort.order == .forward, forKey: "sortAscending")
        }
        
        // Save High CPU settings
        UserDefaults.standard.set(highCpuThreshold, forKey: "highCpuThreshold")
        UserDefaults.standard.set(groupProcessesByApp, forKey: "groupProcessesByApp")
        UserDefaults.standard.set(showCpuTrendChart, forKey: "showCpuTrendChart")
    }
    
    private func applySortOrder(field: String, ascending: Bool) {
        let order: SortOrder = ascending ? .forward : .reverse
        
        switch field {
        case "pid":
            sortOrder = [KeyPathComparator(\ProcessInfo.pid, order: order)]
        case "name":
            sortOrder = [KeyPathComparator(\ProcessInfo.name, order: order)]
        case "cpu":
            sortOrder = [KeyPathComparator(\ProcessInfo.cpuUsage, order: order)]
        case "memory":
            sortOrder = [KeyPathComparator(\ProcessInfo.memoryMB, order: order)]
        case "status":
            sortOrder = [KeyPathComparator(\ProcessInfo.status, order: order)]
        case "runtime":
            sortOrder = [KeyPathComparator(\ProcessInfo.runTime, order: order)]
        default:
            break
        }
    }
    
    private func getSortFieldName(from comparator: KeyPathComparator<ProcessInfo>) -> String {
        // This is a simplified version - in production you'd want a more robust solution
        switch comparator.keyPath {
        case \ProcessInfo.pid:
            return "pid"
        case \ProcessInfo.name:
            return "name"
        case \ProcessInfo.cpuUsage:
            return "cpu"
        case \ProcessInfo.memoryMB:
            return "memory"
        case \ProcessInfo.status:
            return "status"
        case \ProcessInfo.runTime:
            return "runtime"
        default:
            return "unknown"
        }
    }
    
    // MARK: - Column Management
    
    func updateColumnWidth(for column: String, width: CGFloat) {
        columnWidths[column] = width
        savePreferences()
    }
    
    func resetColumnWidths() {
        columnWidths = [
            "pid": 60,
            "name": 250,
            "cpu": 100,
            "memory": 120,
            "status": 100,
            "threads": 80,
            "runtime": 100,
            "parent_pid": 80,
            "user_time": 80,
            "system_time": 80
        ]
        savePreferences()
    }
    
    // MARK: - Column Reordering
    
    func moveColumn(from source: IndexSet, to destination: Int) {
        columnOrder.move(fromOffsets: source, toOffset: destination)
        savePreferences()
    }
    
    func resetColumnOrder() {
        columnOrder = [
            "pid", "name", "cpu", "memory", "status", "threads", 
            "runtime", "parent_pid", "user_time", "system_time"
        ]
        savePreferences()
    }
    
    func hideColumn(_ columnId: String) {
        if let index = columnOrder.firstIndex(of: columnId) {
            columnOrder.remove(at: index)
            savePreferences()
        }
    }
    
    func showColumn(_ columnId: String, at position: Int? = nil) {
        if !columnOrder.contains(columnId) {
            if let pos = position, pos < columnOrder.count {
                columnOrder.insert(columnId, at: pos)
            } else {
                columnOrder.append(columnId)
            }
            savePreferences()
        }
    }
}