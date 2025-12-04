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
                        .applicationVersion: "0.2.0"
                    ])
                }
            }
            
            ReaperCommands(appState: appState)
        }
    }
}