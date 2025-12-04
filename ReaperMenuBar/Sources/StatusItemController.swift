import AppKit
import SwiftUI

class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var systemMonitor: SystemMonitor
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
        self.systemMonitor = SystemMonitor()
        super.init()
        setupStatusItem()
        startMonitoring()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = "🔄 Loading..."
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
        let cpuItem = NSMenuItem(title: "CPU Usage: --", action: nil, keyEquivalent: "")
        cpuItem.isEnabled = false
        menu?.addItem(cpuItem)

        // CPU temperature item (non-clickable, just info)
        let tempItem = NSMenuItem(title: "CPU Temperature: --", action: nil, keyEquivalent: "")
        tempItem.isEnabled = false
        menu?.addItem(tempItem)

        // Disk space item (non-clickable, just info)
        let diskItem = NSMenuItem(title: "Disk Available: --", action: nil, keyEquivalent: "")
        diskItem.isEnabled = false
        menu?.addItem(diskItem)

        menu?.addItem(NSMenuItem.separator())

        // Data source indicator
        let sourceItem = NSMenuItem(title: "Source: --", action: nil, keyEquivalent: "")
        sourceItem.isEnabled = false
        menu?.addItem(sourceItem)

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
        updateSystemDisplay()
        
        // Start timer with adaptive interval
        scheduleNextUpdate()
    }
    
    private func scheduleNextUpdate() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: currentRefreshInterval, repeats: false) { [weak self] _ in
            self?.updateSystemDisplay()
            self?.adjustRefreshRate()
            self?.scheduleNextUpdate()
        }
    }
    
    private func updateSystemDisplay() {
        // Use Task to call async methods without blocking
        Task {
            // Fetch all metrics asynchronously (no semaphores, no deadlocks)
            let cpuUsage = await systemMonitor.getCurrentCPUUsage()
            let temperature = await systemMonitor.getCurrentTemperature()
            let diskMetrics = await systemMonitor.getDiskMetrics()

            let cpuInt = Int(cpuUsage)
            let tempInt = Int(temperature)

            // Update UI on main thread
            await MainActor.run {
                // Update button title with CPU, Temperature, and Disk
                if let button = self.statusItem?.button {
                    // Get emojis for metrics
                    let cpuEmoji = self.emojiForCPU(cpuInt)
                    let tempEmoji = self.emojiForTemperature(tempInt)
                    let diskEmoji = self.emojiForDisk(diskMetrics?.usagePercent ?? 0)

                    // Format display string: CPU | Temp | Disk
                    var displayString = ""

                    // CPU part
                    displayString += "\(cpuEmoji)\(cpuInt)%"

                    // Temperature part
                    displayString += " \(tempEmoji)\(tempInt)°"

                    // Disk part
                    if let disk = diskMetrics {
                        displayString += " \(diskEmoji)\(disk.formattedAvailable)"
                    }

                    button.title = displayString

                    // Apply monospaced font for consistent width
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                    ]

                    button.attributedTitle = NSAttributedString(string: button.title, attributes: attributes)
                }

                // Update menu items
                if self.menu?.items.count ?? 0 >= 5 {
                    self.menu?.items[0].title = String(format: "CPU Usage: %.1f%%", cpuUsage)
                    self.menu?.items[1].title = String(format: "CPU Temperature: %.0f°C", temperature)

                    if let disk = diskMetrics {
                        self.menu?.items[2].title = String(format: "Disk Available: %@ (%.0f%% used)",
                                                          disk.formattedAvailable,
                                                          disk.usagePercent)
                    }

                    // Update source indicator (index 4, after separator at 3)
                    let sourceText = self.systemMonitor.isUsingXPC ? "XPC Service" : "Local FFI"
                    let sourceIcon = self.systemMonitor.isUsingXPC ? "🔗" : "⚡"
                    self.menu?.items[4].title = "Source: \(sourceIcon) \(sourceText)"
                }
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
    
    private func emojiForDisk(_ usagePercent: Float) -> String {
        switch usagePercent {
        case 0..<70:
            return "🟢"  // Green - plenty of space
        case 70..<90:
            return "🟡"  // Yellow - getting full
        default:
            return "🔴"  // Red - critical, almost full
        }
    }

    private func emojiForTemperature(_ temp: Int) -> String {
        switch temp {
        case 0..<50:
            return "🟢"  // Green - cool
        case 50..<70:
            return "🟡"  // Yellow - warm
        case 70..<85:
            return "🟠"  // Orange - hot
        default:
            return "🔴"  // Red - very hot
        }
    }
    
    private func adjustRefreshRate() {
        // Use cached value to avoid blocking (async updates happen in updateSystemDisplay)
        let currentCPU = Int(systemMonitor.getCachedCPUUsage())
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
        systemMonitor.cleanup()
        
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}