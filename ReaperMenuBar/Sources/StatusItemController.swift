import AppKit
import SwiftUI

class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var cpuMonitor: CPUMonitor
    private var updateTimer: Timer?
    private var menu: NSMenu?
    
    // Adaptive refresh settings
    private var currentRefreshInterval: TimeInterval = 2.0
    private let minRefreshInterval: TimeInterval = 1.0
    private let maxRefreshInterval: TimeInterval = 10.0
    private let idleRefreshInterval: TimeInterval = 5.0
    
    // Track CPU changes for adaptive updates
    private var lastCPUValue: Int = 0
    private var stableReadingsCount: Int = 0
    private let stableThreshold: Int = 5 // After 5 stable readings, slow down
    
    override init() {
        self.cpuMonitor = CPUMonitor()
        super.init()
        setupStatusItem()
        startMonitoring()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = "CPU: --"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create menu for right-click
        setupMenu()
    }
    
    private func setupMenu() {
        menu = NSMenu()
        
        // CPU usage item (non-clickable, just info)
        let cpuItem = NSMenuItem(title: "CPU Usage", action: nil, keyEquivalent: "")
        cpuItem.isEnabled = false
        menu?.addItem(cpuItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        // Open Reaper item
        let openReaperItem = NSMenuItem(title: "Open Reaper", action: #selector(openReaper), keyEquivalent: "o")
        openReaperItem.target = self
        menu?.addItem(openReaperItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        // Settings submenu (future)
        let settingsItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        let settingsSubmenu = NSMenu()
        
        let fastItem = NSMenuItem(title: "Fast (1s)", action: #selector(setFastRefresh), keyEquivalent: "")
        fastItem.target = self
        settingsSubmenu.addItem(fastItem)
        
        let normalItem = NSMenuItem(title: "Normal (2s)", action: #selector(setNormalRefresh), keyEquivalent: "")
        normalItem.target = self
        settingsSubmenu.addItem(normalItem)
        
        let slowItem = NSMenuItem(title: "Slow (5s)", action: #selector(setSlowRefresh), keyEquivalent: "")
        slowItem.target = self
        settingsSubmenu.addItem(slowItem)
        
        settingsItem.submenu = settingsSubmenu
        menu?.addItem(settingsItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        // Quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)
    }
    
    private func startMonitoring() {
        // Initial update
        updateCPUDisplay()
        
        // Start timer with adaptive interval
        scheduleNextUpdate()
    }
    
    private func scheduleNextUpdate() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: currentRefreshInterval, repeats: false) { [weak self] _ in
            self?.updateCPUDisplay()
            self?.adjustRefreshRate()
            self?.scheduleNextUpdate()
        }
    }
    
    private func updateCPUDisplay() {
        let cpuUsage = cpuMonitor.getCurrentCPUUsage()
        let cpuInt = Int(cpuUsage)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update button title
            if let button = self.statusItem?.button {
                // Get emoji based on CPU usage
                let emoji = self.emojiForCPU(cpuInt)
                
                // Format with emoji and percentage
                button.title = "\(emoji) \(cpuInt)%"
                
                // Font weight based on CPU usage
                let weight: NSFont.Weight
                if cpuInt > 80 {
                    weight = .bold
                } else if cpuInt > 50 {
                    weight = .medium
                } else {
                    weight = .regular
                }
                
                // Apply monospaced font for consistent number width
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: weight)
                ]
                
                button.attributedTitle = NSAttributedString(string: button.title, attributes: attributes)
            }
            
            // Update menu if visible
            if let cpuMenuItem = self.menu?.items.first {
                cpuMenuItem.title = String(format: "CPU Usage: %.1f%%", cpuUsage)
            }
        }
    }
    
    private func emojiForCPU(_ cpuUsage: Int) -> String {
        switch cpuUsage {
        case 0..<30:
            return "🟢"  // Green - system healthy
        case 30..<70:
            return "🟡"  // Yellow - moderate load
        default:
            return "🔴"  // Red - high load
        }
    }
    
    private func adjustRefreshRate() {
        let currentCPU = Int(cpuMonitor.getCurrentCPUUsage())
        let cpuDelta = abs(currentCPU - lastCPUValue)
        
        if cpuDelta < 3 {
            // CPU is stable
            stableReadingsCount += 1
            if stableReadingsCount >= stableThreshold {
                // Been stable for a while, slow down
                currentRefreshInterval = min(currentRefreshInterval * 1.2, maxRefreshInterval)
                stableReadingsCount = stableThreshold // Cap it
            }
        } else {
            // CPU changed significantly
            stableReadingsCount = 0
            if cpuDelta > 10 {
                // Big change, speed up monitoring
                currentRefreshInterval = minRefreshInterval
            } else {
                // Moderate change
                currentRefreshInterval = 2.0
            }
        }
        
        lastCPUValue = currentCPU
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Show menu on right-click
            if let menu = menu {
                statusItem?.menu = menu
                statusItem?.button?.performClick(nil)
                statusItem?.menu = nil // Remove menu after showing
            }
        } else {
            // Left click - open Reaper
            openReaper()
        }
    }
    
    @objc private func openReaper() {
        // Try to find Reaper.app in the parent directory
        let appPath = "/Users/santifdezmunoz/Documents/repos/BelowZero/Reaper/Reaper.app"
        
        if FileManager.default.fileExists(atPath: appPath) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath),
                                              configuration: NSWorkspace.OpenConfiguration(),
                                              completionHandler: nil)
        } else {
            // Try to launch by name
            NSWorkspace.shared.launchApplication("Reaper")
        }
    }
    
    @objc private func setFastRefresh() {
        currentRefreshInterval = 1.0
        stableReadingsCount = 0
        scheduleNextUpdate()
    }
    
    @objc private func setNormalRefresh() {
        currentRefreshInterval = 2.0
        stableReadingsCount = 0
        scheduleNextUpdate()
    }
    
    @objc private func setSlowRefresh() {
        currentRefreshInterval = 5.0
        stableReadingsCount = 0
        scheduleNextUpdate()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        cpuMonitor.cleanup()
        
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}