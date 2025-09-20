import SwiftUI

// MARK: - Focused Values for keyboard shortcuts

struct SelectedProcessKey: FocusedValueKey {
    typealias Value = ProcessInfo
}

struct RustBridgeKey: FocusedValueKey {
    typealias Value = RustBridge
}

struct NotificationManagerKey: FocusedValueKey {
    typealias Value = NotificationManager
}

struct SelectedProcessesKey: FocusedValueKey {
    typealias Value = Set<UInt32>
}

struct AllProcessesKey: FocusedValueKey {
    typealias Value = Set<UInt32>
}

extension FocusedValues {
    var selectedProcess: ProcessInfo? {
        get { self[SelectedProcessKey.self] }
        set { self[SelectedProcessKey.self] = newValue }
    }
    
    var rustBridge: RustBridge? {
        get { self[RustBridgeKey.self] }
        set { self[RustBridgeKey.self] = newValue }
    }
    
    var notificationManager: NotificationManager? {
        get { self[NotificationManagerKey.self] }
        set { self[NotificationManagerKey.self] = newValue }
    }
    
    var selectedProcesses: Set<UInt32>? {
        get { self[SelectedProcessesKey.self] }
        set { self[SelectedProcessesKey.self] = newValue }
    }
    
    var allProcesses: Set<UInt32>? {
        get { self[AllProcessesKey.self] }
        set { self[AllProcessesKey.self] = newValue }
    }
}