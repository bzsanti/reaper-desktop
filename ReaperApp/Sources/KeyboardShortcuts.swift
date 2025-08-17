import SwiftUI

// MARK: - Keyboard Shortcut Commands

struct ReaperCommands: Commands {
    @ObservedObject var appState: AppState
    @FocusedValue(\.selectedProcess) var selectedProcess: ProcessInfo?
    @FocusedValue(\.rustBridge) var rustBridge: RustBridge?
    @FocusedValue(\.notificationManager) var notificationManager: NotificationManager?
    
    var body: some Commands {
        // Process Commands
        CommandMenu("Process") {
            Section {
                Button("Terminate Process") {
                    terminateSelectedProcess()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(selectedProcess == nil)
                
                Button("Force Kill Process") {
                    forceKillSelectedProcess()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(selectedProcess == nil)
                
                Divider()
                
                Button("Suspend Process") {
                    suspendSelectedProcess()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(selectedProcess == nil)
                
                Button("Resume Process") {
                    resumeSelectedProcess()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(selectedProcess == nil)
            }
            
            Divider()
            
            Button("Show Process Details") {
                showProcessDetails()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(selectedProcess == nil)
            
            Button("Copy Process Info") {
                copyProcessInfo()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(selectedProcess == nil)
        }
        
        // View Commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Details Panel") {
                appState.shouldShowDetails.toggle()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            
            Divider()
            
            Button("Refresh Processes") {
                refreshProcessList()
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        
        // Edit Commands
        CommandGroup(after: .pasteboard) {
            Section {
                Button("Search Processes") {
                    appState.isSearchFieldFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Clear Search") {
                    appState.searchText = ""
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
    
    // MARK: - Actions
    
    private func terminateSelectedProcess() {
        guard let process = selectedProcess else { return }
        
        appState.processToAct = process
        appState.showTerminateConfirmation = true
    }
    
    private func forceKillSelectedProcess() {
        guard let process = selectedProcess else { return }
        
        appState.processToAct = process
        appState.showForceKillConfirmation = true
    }
    
    private func suspendSelectedProcess() {
        guard let process = selectedProcess,
              let bridge = rustBridge,
              let notifications = notificationManager else { return }
        
        let success = bridge.suspendProcess(process.pid)
        
        if success {
            notifications.show(
                .success,
                title: "Process Suspended",
                message: "\(process.name) (PID: \(process.pid)) was suspended"
            )
            bridge.refresh()
        } else {
            notifications.show(
                .error,
                title: "Failed to Suspend",
                message: "Could not suspend \(process.name)"
            )
        }
    }
    
    private func resumeSelectedProcess() {
        guard let process = selectedProcess,
              let bridge = rustBridge,
              let notifications = notificationManager else { return }
        
        let success = bridge.resumeProcess(process.pid)
        
        if success {
            notifications.show(
                .success,
                title: "Process Resumed",
                message: "\(process.name) (PID: \(process.pid)) was resumed"
            )
            bridge.refresh()
        } else {
            notifications.show(
                .error,
                title: "Failed to Resume",
                message: "Could not resume \(process.name)"
            )
        }
    }
    
    private func showProcessDetails() {
        appState.shouldShowDetails = true
    }
    
    private func copyProcessInfo() {
        guard let process = selectedProcess,
              let notifications = notificationManager else { return }
        
        let info = """
        Process: \(process.name)
        PID: \(process.pid)
        CPU: \(String(format: "%.1f%%", process.cpuUsage))
        Memory: \(formatMemory(process.memoryMB))
        Status: \(process.status)
        Threads: \(process.threadCount)
        Runtime: \(formatRuntime(process.runTime))
        """
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        
        notifications.show(
            .info,
            title: "Copied to Clipboard",
            message: "Process information copied"
        )
    }
    
    private func refreshProcessList() {
        rustBridge?.refresh()
        notificationManager?.show(
            .info,
            title: "Refreshed",
            message: "Process list updated"
        )
    }
    
    // Helper functions (should be in a shared location)
    private func formatMemory(_ mb: Double) -> String {
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024)
        }
    }
    
    private func formatRuntime(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

// MARK: - Focused Values

struct SelectedProcessKey: FocusedValueKey {
    typealias Value = ProcessInfo
}

struct RustBridgeKey: FocusedValueKey {
    typealias Value = RustBridge
}

struct NotificationManagerKey: FocusedValueKey {
    typealias Value = NotificationManager
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
}

// MARK: - Keyboard Shortcut View Modifier

struct KeyboardShortcutHandler: ViewModifier {
    @ObservedObject var appState: AppState
    let selectedProcess: ProcessInfo?
    let rustBridge: RustBridge
    let notificationManager: NotificationManager
    
    func body(content: Content) -> some View {
        content
            .focusedValue(\.selectedProcess, selectedProcess)
            .focusedValue(\.rustBridge, rustBridge)
            .focusedValue(\.notificationManager, notificationManager)
            // onKeyPress is only available in macOS 14+
            // For macOS 13 compatibility, keyboard shortcuts are handled via menu commands
    }
}

extension View {
    func withKeyboardShortcuts(
        appState: AppState,
        selectedProcess: ProcessInfo?,
        rustBridge: RustBridge,
        notificationManager: NotificationManager
    ) -> some View {
        modifier(KeyboardShortcutHandler(
            appState: appState,
            selectedProcess: selectedProcess,
            rustBridge: rustBridge,
            notificationManager: notificationManager
        ))
    }
}