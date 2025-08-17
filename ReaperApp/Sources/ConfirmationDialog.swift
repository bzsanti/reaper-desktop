import SwiftUI

// MARK: - Confirmation Dialog View

struct ConfirmationDialog: View {
    let title: String
    let message: String
    let destructiveActionTitle: String
    let destructiveAction: () -> Void
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            // Title
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            // Message
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(destructiveActionTitle) {
                    destructiveAction()
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
        .padding(30)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Process Action Confirmation

struct ProcessActionConfirmation: View {
    let process: ProcessInfo
    let action: ProcessAction
    let onConfirm: () -> Void
    @Binding var isPresented: Bool
    
    enum ProcessAction {
        case terminate
        case forceKill
        case suspendMultiple(count: Int)
        case terminateMultiple(count: Int)
        
        var title: String {
            switch self {
            case .terminate:
                return "Terminate Process?"
            case .forceKill:
                return "Force Kill Process?"
            case .suspendMultiple(let count):
                return "Suspend \(count) Processes?"
            case .terminateMultiple(let count):
                return "Terminate \(count) Processes?"
            }
        }
        
        var message: String {
            switch self {
            case .terminate:
                return "This will send a termination signal (SIGTERM) to the process, allowing it to clean up before exiting."
            case .forceKill:
                return "This will immediately kill the process (SIGKILL) without allowing it to clean up. Use with caution as it may cause data loss."
            case .suspendMultiple(let count):
                return "This will suspend \(count) processes. They can be resumed later."
            case .terminateMultiple(let count):
                return "This will terminate \(count) processes. This action cannot be undone."
            }
        }
        
        var actionTitle: String {
            switch self {
            case .terminate, .terminateMultiple:
                return "Terminate"
            case .forceKill:
                return "Force Kill"
            case .suspendMultiple:
                return "Suspend"
            }
        }
        
        var isDestructive: Bool {
            switch self {
            case .terminate, .forceKill, .terminateMultiple:
                return true
            case .suspendMultiple:
                return false
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: action.isDestructive ? "exclamationmark.triangle.fill" : "pause.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(action.isDestructive ? .red : .orange)
            
            // Title
            Text(action.title)
                .font(.headline)
            
            // Process Info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Process:")
                        .foregroundColor(.secondary)
                    Text(process.name)
                        .fontWeight(.medium)
                }
                HStack {
                    Text("PID:")
                        .foregroundColor(.secondary)
                    Text("\(process.pid)")
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Warning Message
            Text(action.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(action.actionTitle) {
                    onConfirm()
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(action.isDestructive ? .red : .orange)
                .controlSize(.large)
            }
        }
        .padding(30)
        .frame(width: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
}