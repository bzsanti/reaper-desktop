# Changelog

All notable changes to Reaper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.6] - 2025-08-21

### Added
- 🔥 **Real-time CPU Sampling**: High-frequency CPU monitoring with advanced analysis
  - RealTimeCpuSample structure for 50-100ms interval sampling
  - CpuSamplingBuffer with circular buffer for memory-efficient storage
  - AggregatedCpuMetrics for statistical analysis over time periods
  - Context switches and interrupt tracking with delta calculations
- 📊 **Flame Graph Support**: Performance profiling visualization capabilities
  - FlameGraphData and FlameGraphNode structures for hierarchical stack trace analysis
  - FlameGraphBuilder for constructing graphs from stack traces
  - Export to folded format and JSON for compatibility with external tools
  - Hot function analysis and performance bottleneck identification
- 💾 **CPU History Persistence**: Long-term monitoring data storage
  - CpuHistoryStore with JSONL file-based persistence
  - Daily file rotation with automatic cleanup of old data
  - Configurable retention periods and memory buffer sizes
  - Historical data querying and statistical analysis
  - Temperature and frequency tracking over time
- 🌡️ **Thermal Monitoring**: Advanced thermal management and throttling detection
  - ThermalMonitor with native macOS IOKit/SMC integration
  - Multiple thermal sensor support (CPU cores, package, GPU, memory, ambient)
  - Real-time thermal throttling detection with severity levels
  - Temperature history tracking and thermal event logging
  - Integration with Apple's System Management Controller (SMC)

### Enhanced
- 🚀 **CPU Analysis Architecture**: Phase 2 advanced monitoring capabilities complete
  - Extended CpuAnalyzer with real-time sampling infrastructure
  - Thermal integration for comprehensive system health monitoring
  - Performance profiling tools for advanced debugging workflows
  - Historical data persistence for trend analysis and capacity planning

### Technical
- 📦 **New Dependencies**: Added chrono crate for timestamp handling
- 🧪 **Test Coverage**: Added comprehensive unit tests for all new modules
- 🔧 **Build System**: Updated Cargo.toml configurations for new features
- 📚 **Documentation**: Enhanced module documentation with usage examples

### Architecture
- 🏗️ **Advanced Monitoring Stack**: Complete CPU analysis ecosystem
  - Real-time sampling layer for high-frequency data collection
  - Flame graph layer for performance visualization and profiling
  - Persistence layer for historical data management
  - Thermal layer for system health and throttling detection

## [0.4.5] - 2025-08-20

### Added
- 🌳 **Process Tree View Integration**: Hierarchical process view within main "All Processes" tab
  - Toggle button to switch between flat list and hierarchical tree view
  - Animated transitions between view modes (0.3s ease-in-out)
  - Tree structure shows parent-child process relationships
  - Expandable/collapsible process nodes
  - Interactive checkboxes for multi-process selection in tree view
- 👁️ **Column Visibility Controls**: Advanced table column management
  - Dropdown menu to show/hide specific columns (PID, Name, CPU, Memory, etc.)
  - Column visibility state persistence across app restarts
  - Conditional column rendering with macOS 14.4+ requirement
  - Smooth column animations when toggling visibility

### Fixed
- 🔢 **PID Formatting**: PIDs no longer display thousands separators (e.g., "1,234" now shows as "1234")
- ☑️ **Tree View Checkboxes**: Properly rendering interactive checkboxes in tree view
  - Replaced non-functional Image components with proper Button components
  - Added visual feedback with accent color for selected items
  - Fixed checkbox interaction and state management
- 🔄 **CPU Data Consistency**: Synchronized data between main view and detail panel
  - Added process synchronization in onReceive for real-time updates
  - Fixed CPU percentage mismatches between different views
  - Improved data refresh consistency across UI components
- 🎯 **Process Selection**: Enhanced process tracking and selection persistence

### Changed
- 📱 **System Requirements**: Minimum macOS requirement updated to 14.4 for advanced table features
  - Added `@available(macOS 14.4, *)` attribute to ProcessListView
  - Conditional rendering for older macOS versions with fallback message
  - Updated Info.plist with LSMinimumSystemVersion set to "14.4"
- 🏗️ **UI Architecture**: Process tree view now embedded in main tab instead of separate tab
  - Removed dedicated tree view tab (tag 5)
  - Updated search visibility condition for integrated design
  - Improved toolbar layout with tree/list toggle button
- 🔧 **Build System**: Enhanced build reliability with absolute paths
  - Updated build_app_bundle.sh with absolute path references
  - Improved library linking with install_name_tool
  - Build timestamp: 20250820225308

### Technical Details
- Implemented conditional content rendering with SwiftUI animations
- Enhanced AppState column management with persistent storage
- Added process selection synchronization across view modes
- Improved FFI bridge reliability for process data consistency
- Updated version strings in ContentView.swift and Info.plist

## [0.4.4] - 2025-08-20

### Added
- Initial process tree view as separate tab
- Basic toggle functionality for tree/list views

### Fixed
- Button height issues in toolbar
- Initial compilation errors for tree view integration

## [0.4.3] - 2025-08-20

### Added
- Foundation for tree view functionality
- Process hierarchy data structures

### Fixed
- Various UI layout improvements
- Performance optimizations for process monitoring

## [0.4.2] - 2025-08-19

### Fixed
- Compilation issues with column visibility
- UI consistency improvements

## [0.4.1] - 2025-08-18

### Added
- 📊 **Menu Bar Integration**: System metrics now display in macOS menu bar
  - CPU usage with color-coded emojis (🟢 <30%, 🟡 30-70%, 🔴 >70%)
  - Disk space available with visual indicators (💾 normal, 📀 warning, 💿 critical)
  - Compact display format: "🟢45% 💾250GB"
  - Right-click menu with detailed system information
  - Configurable refresh rates (Fast/Normal/Slow)
  - One-click launch of main Reaper application

### Enhanced
- **ReaperMenuBar App**: Standalone menu bar monitor
  - Minimal resource usage with adaptive refresh rates
  - Smart caching to reduce FFI calls
  - Runs as background app (LSUIElement)
  - Can be set as login item for automatic startup
  
### Fixed
- Improved icon handling in build scripts
- Better library path resolution for menu bar app

### Technical
- SystemMonitor class replaces CPUMonitor with disk support
- FFI bindings for both CPU and disk monitoring in menu bar
- Optimized build scripts for both main and menu bar apps

## [0.4.0] - 2025-08-18

### Added
- 💾 **Disk Monitor**: Complete disk monitoring system with real-time metrics
  - Primary disk space display in header bar with color-coded usage
  - Real-time disk usage tracking for all mounted volumes
  - Disk type detection (HDD, SSD, Network, Removable)
  - File system information for each disk
  - Space available, used, and total metrics
  - Visual indicators: Green (<70%), Orange (70-90%), Red (>90% usage)
  - Formatted display with appropriate units (GB/TB)
  - Support for multiple disk monitoring and growth rate tracking
  
### Technical
- New Rust disk monitor module using sysinfo
- FFI bridge with CDiskInfo and CDiskList structures
- Disk growth history tracking (60 samples)
- Automatic disk type detection based on mount points
- Integration with Swift UI through RustBridge

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