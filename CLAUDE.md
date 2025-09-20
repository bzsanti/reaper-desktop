# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

### Full Application Build
```bash
./build_app_bundle.sh    # Complete build and package into Reaper.app
open Reaper.app          # Launch the application
```

### Development Build
```bash
# Build Rust libraries only
cargo build --release

# Build Swift app for development
cd ReaperApp && swift run

# Alternative: Use Makefile
make all                 # Build everything
make run                 # Build and run from CLI
make clean              # Clean all build artifacts
make test              # Run all tests
```

### Testing
```bash
cargo test              # Run Rust tests
cd ReaperApp && swift test  # Run Swift tests (if available)
```

## Architecture Overview

### Core Structure
The project follows a modular architecture with Rust backend and Swift frontend:

```
Reaper/
├── core/               # Platform abstraction layer (Rust)
│   └── platform/       # OS-specific implementations (macos, windows)
├── monitors/           # System monitoring modules (Rust)
│   ├── cpu/           # CPU monitoring with FFI exports
│   ├── memory/        # Memory monitoring (placeholder)
│   ├── disk/          # Disk monitoring (placeholder)
│   └── network/       # Network monitoring (placeholder)
├── ReaperApp/         # SwiftUI macOS application
│   └── Sources/       # Swift source files
└── Reaper.app/        # Built application bundle
```

### FFI Bridge Architecture
The Rust-Swift communication happens through C FFI:

1. **Rust Side** (`monitors/cpu/src/ffi.rs`):
   - Exports C-compatible functions (`#[no_mangle] pub extern "C"`)
   - Uses static Lazy singletons for ProcessMonitor and CpuAnalyzer
   - Converts Rust types to C-compatible structs (CProcessInfo, CProcessList, etc.)
   - Memory management: Rust allocates, Swift must call free functions

2. **Swift Side** (`ReaperApp/Sources/RustBridge.swift`):
   - Imports C functions via `@_silgen_name` declarations
   - Manages memory lifecycle (calls free functions)
   - Converts C types to Swift types (ProcessInfo, CpuMetrics)
   - Uses @MainActor for UI updates and async operations

### Key Design Patterns

1. **Platform Abstraction** (`core/src/platform/`):
   - Trait-based design for cross-platform support
   - ProcessManager, SystemMonitor, KernelOperations, ProcessAnalyzer traits
   - Platform-specific implementations in macos/ and windows/ modules

2. **Process States**:
   - Running, Sleeping, Zombie, UninterruptibleSleep, Unkillable
   - Detection of problematic processes through kernel interface
   - Advanced metrics: context switches, I/O wait, page faults

3. **UI State Management**:
   - AppState class for global app state and preferences
   - UserDefaults for persistence
   - NotificationManager for toast notifications
   - Adaptive refresh rates based on app activity

## Version Management Rules (CRITICAL)

### Semantic Versioning X.Y.Z

1. **Major Version (X.0.0)**: ONLY with explicit user authorization
2. **Minor Version (0.X.0)**: AUTO-INCREMENT for new features
3. **Patch Version (0.0.X)**: AUTO-INCREMENT for bug fixes
4. **Build Version**: ALWAYS update with YYYYMMDDHHmmss format

### Files to Update
- `ReaperApp/Sources/ContentView.swift` - appVersion and buildVersion constants
- `ReaperApp/Info.plist` - CFBundleShortVersionString and CFBundleVersion
- `CHANGELOG.md` - Document changes under appropriate version

Current Version: 0.4.5

## Key Components

### Process Management
- **RustBridge.swift**: Main interface between Swift and Rust
- **ProcessMonitor** (Rust): Collects process information using sysinfo
- **KernelInterface** (Rust): Low-level process control (kill, suspend, resume)
- **ProcessAnalyzer** (Rust): Advanced detection (unkillable, I/O wait analysis)

### UI Views
- **ContentView**: Main app container with tabs and header
- **ProcessListView**: All processes table with sorting/filtering
- **HighCpuView**: High CPU processes with trend charts
- **SystemMetricsView**: System-wide metrics display
- **ProcessDetailView**: Detailed process information panel

### State Management
- **AppState**: Global preferences and UI state
- **NotificationManager**: Toast notification system
- **ConfirmationDialog**: Safety dialogs for destructive actions

## FFI Memory Management

Critical: Swift must free memory allocated by Rust:
- `free_process_list()` after `get_all_processes()`
- `free_cpu_metrics()` after `get_cpu_metrics()`
- `free_process_details()` after `get_process_details()`

## Performance Considerations

- Default refresh rate: 1Hz (increases to 2Hz when active)
- Adaptive refresh: Slows to 5-10s when idle/background
- Process list sorting happens in Swift for UI responsiveness
- Rust backend caches system calls for 1 second

## Known Build Issues

- Swift Package Manager may not find Rust libraries - ensure `cargo build --release` runs first
- App bundle requires manual library copying (handled by build_app_bundle.sh)
- Some Rust warnings about unused imports are expected during development

## Testing Strategy

- Rust unit tests for core logic and platform abstraction
- Manual testing for UI interactions
- Process termination requires admin privileges for system processes
- Test unkillable detection with processes in uninterruptible sleep state