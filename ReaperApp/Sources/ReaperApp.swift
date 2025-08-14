import SwiftUI

@main
struct ReaperApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Reaper") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Reaper",
                        .applicationVersion: "0.1.0"
                    ])
                }
            }
            
            CommandMenu("Process") {
                Button("Terminate Process") {
                    appState.shouldTerminateProcess = true
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button("Force Kill Process") {
                    appState.shouldForceKillProcess = true
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Suspend Process") {
                    appState.shouldSuspendProcess = true
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                
                Button("Resume Process") {
                    appState.shouldResumeProcess = true
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                
                Divider()
                
                Button("Show Process Details") {
                    appState.shouldShowDetails = true
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            
            CommandGroup(after: .sidebar) {
                Button("Refresh") {
                    appState.shouldRefresh = true
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var shouldTerminateProcess = false
    @Published var shouldForceKillProcess = false
    @Published var shouldSuspendProcess = false
    @Published var shouldResumeProcess = false
    @Published var shouldShowDetails = false
    @Published var shouldRefresh = false
}