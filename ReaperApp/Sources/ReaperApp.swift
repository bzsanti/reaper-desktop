import SwiftUI

@main
struct ReaperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
        }
    }
}