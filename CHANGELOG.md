# Changelog

All notable changes to Reaper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2025-08-17

### Added
- 🚦 **CPU Limiting Visibility**: Visual indicators for CPU-limited processes
  - Badge icons in process list showing which processes have CPU limits
  - Context menu shows current CPU limit percentage
  - Checkmarks indicate active limit presets in menu
  - New "CPU Limited Processes" card in System Metrics view
  - Real-time tracking of all limited processes with details
  - One-click removal of CPU limits from System Metrics
  - Limit type indicators (Nice, CPU Affinity, cpulimit, Combined)

### Fixed
- Build timestamp showing January instead of August (20250116 → 20250817)
- Build script directory creation for Frameworks folder

### Technical
- Added FFI functions: `get_all_cpu_limits()`, `has_process_limit()`
- New CCpuLimitList and CCpuLimit structs for passing limit data
- RustBridge tracks limited processes in @Published properties
- Automatic refresh of CPU limits after changes

## [0.3.0] - 2025-01-16

### Added
- 💾 **Memory Monitor**: Complete memory monitoring system
  - Real-time memory usage visualization with circular progress chart
  - Memory breakdown (total, used, available, free, swap)
  - Top memory consuming processes list
  - Memory leak detection (processes with continuous growth > 1MB/min)
  - Memory pressure indicator (Low, Normal, High, Critical)
  - Process memory trends and growth rate tracking
  - Three view modes: Overview, Top Processes, Memory Leaks
  - Compatible with macOS 13+ (custom charts instead of SectorMark)

### Technical
- New Rust memory monitor module with sysinfo
- FFI bridge for memory metrics
- Automatic memory history tracking (60 samples)
- Linear regression for memory growth detection

## [0.2.1] - 2025-01-16

### Enhanced
- 📊 **Enhanced High CPU Tab**: Complete redesign with advanced features
  - Real-time CPU trend chart (60-second history)
  - Table view with sortable columns matching All Processes view
  - Process impact indicators (context switches, I/O wait, unkillable)
  - CPU usage trend indicators (up/down arrows)
  - Configurable CPU threshold (5-100%)
  - Group by application feature
  - Context menu with all process actions
  - Batch operations support
  - Settings panel with persistent preferences

### Changed
- High CPU tab now uses table view consistent with All Processes
- Removed redundant chart/card dual display
- Improved visual feedback with progress bars and icons
- Unified process actions across all views

### Fixed
- Main actor isolation issues in timer callbacks
- Proper persistence of High CPU settings
- Build script executable copying issue

## [0.2.0] - 2024-08-16

### Added
- 🛡️ **Confirmation Dialogs**: Safe process termination with visual confirmation dialogs
- 🔔 **Notification System**: Toast notifications with auto-dismiss for all actions
- ⌨️ **Keyboard Shortcuts**: Complete keyboard navigation and control
  - ⌘K: Terminate process
  - ⌘⇧K: Force kill process
  - ⌘P: Pause/suspend process
  - ⌘⇧P: Resume process
  - ⌘I: Show process details
  - ⌘R: Refresh process list
  - ⌘F: Focus search
  - ⌘⇧C: Copy process info
- 💾 **Persistent Preferences**: Settings saved between sessions using UserDefaults
- 🏗️ **Platform Abstraction**: Architecture prepared for Windows support
- 📝 **Process Actions**: Context menu with terminate, kill, suspend, and resume
- 🎨 **Visual Feedback**: Color-coded notifications (success, error, warning, info)
- 📋 **Copy Process Info**: Export process details to clipboard

### Changed
- Improved UI responsiveness with optimized refresh rates
- Better memory management with selective process updates
- Enhanced process detection accuracy
- Refactored code structure for better maintainability

### Fixed
- NSTableView reentrant operation warnings
- Memory leaks in process monitoring
- UI update timing issues
- Process details panel refresh problems

## [0.1.1] - 2024-08-15

### Added
- Process details panel with extended information
- Basic context menu for processes
- System metrics view improvements

### Changed
- Optimized CPU usage monitoring
- Improved process list performance

### Fixed
- Fixed version system display
- Resolved process details panel update issues

## [0.1.0] - 2024-08-14

### Added
- Initial release
- Real-time process monitoring
- CPU and memory usage tracking
- System metrics dashboard
- Native SwiftUI interface
- Rust backend with FFI bridge
- Advanced process detection (zombie, unkillable)
- High CPU process identification
- Process search functionality
- Column sorting capabilities

### Technical
- Modular Rust + Swift architecture
- Minimal system resource impact (<2% CPU idle)
- ~50MB memory footprint
- 1Hz default update rate

---

## Roadmap

### Next Release (0.3.0)
- Column resizing and reordering
- Batch process operations
- Memory monitor implementation
- Advanced process filtering

### Future (0.4.0+)
- Disk and network monitors
- Process dependency graphs
- Historical performance data
- Export capabilities (CSV, JSON)
- Configurable alerts and automation

See [ROADMAP.md](ROADMAP.md) for detailed development plans.