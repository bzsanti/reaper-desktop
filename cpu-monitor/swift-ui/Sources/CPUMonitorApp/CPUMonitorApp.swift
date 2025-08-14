import SwiftUI

@main
struct CPUMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("CPU Monitor")
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}