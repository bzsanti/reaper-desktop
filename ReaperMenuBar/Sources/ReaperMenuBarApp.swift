import SwiftUI
import AppKit

@main
struct ReaperMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock - menu bar only app
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize the menu bar controller
        statusItemController = StatusItemController()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.cleanup()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}