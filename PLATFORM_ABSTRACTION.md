# Platform Abstraction Architecture

## Overview

Reaper has been architected with a platform abstraction layer that enables future cross-platform support while maintaining native performance on each operating system. This document describes the abstraction design and implementation guidelines.

## Architecture

### Core Abstractions

The platform abstraction layer is located in `core/src/platform/` and defines three main traits:

1. **ProcessManager** - Process enumeration and control
2. **SystemMonitor** - System metrics and resource monitoring  
3. **KernelOperations** - Low-level kernel operations

### Directory Structure

```
core/src/platform/
├── mod.rs           # Trait definitions and common types
├── macos/           # macOS implementation
│   ├── mod.rs       # Platform struct
│   ├── process.rs   # ProcessManager impl
│   ├── system.rs    # SystemMonitor impl
│   └── kernel.rs    # KernelOperations impl
└── windows/         # Windows implementation (stubs)
    ├── mod.rs       # Platform struct
    ├── process.rs   # ProcessManager stub
    ├── system.rs    # SystemMonitor stub
    └── kernel.rs    # KernelOperations stub
```

## Platform-Specific Features

### macOS (Implemented)
- Uses `libc` for Unix signals (SIGTERM, SIGKILL, etc.)
- Uses `mach2` for Mach kernel interfaces
- Process control via BSD APIs
- System metrics from `sysinfo` crate

### Windows (Ready for Implementation)
- Will use `windows-rs` for Win32 APIs
- TerminateProcess for process termination
- WMI for system metrics
- Performance Counters for detailed monitoring

## Usage Example

```rust
use reaper_core::platform::MacOSPlatform;

let platform = MacOSPlatform::new();

// Process management
let processes = platform.process_manager().list_processes()?;
platform.process_manager().send_signal(pid, Signal::Terminate)?;

// System monitoring  
let metrics = platform.system_monitor().get_system_metrics()?;

// Kernel operations
platform.kernel_ops().force_kill(pid)?;
```

## Adding Windows Support

When implementing Windows support:

1. Replace stub implementations in `core/src/platform/windows/`
2. Add Windows dependencies to `Cargo.toml`:
   ```toml
   [target.'cfg(target_os = "windows")'.dependencies]
   windows = { version = "0.52", features = ["Win32_System_ProcessStatus"] }
   ```
3. Implement Windows-specific UI (WinUI 3 recommended)
4. Test platform detection and conditional compilation

## Performance Considerations

- Platform abstractions use zero-cost trait objects
- No runtime overhead for platform detection
- Compile-time platform selection via `cfg` attributes
- Native APIs used directly, no translation layers

## Future Enhancements

### Short Term
- Complete Windows process management implementation
- Add Linux support via `/proc` filesystem
- Implement platform-specific error handling

### Long Term  
- Support for container environments (Docker, WSL)
- Remote system monitoring capabilities
- Platform-agnostic plugin system

## Testing

Platform abstractions include unit tests in `core/src/platform/tests.rs`:

```bash
cargo test --package reaper-core --lib platform::tests
```

## Maintaining Platform Parity

When adding new features:

1. Define the trait method in `platform/mod.rs`
2. Implement for macOS in `platform/macos/`
3. Add stub implementation for Windows
4. Document platform differences
5. Add tests for new functionality

## Key Design Decisions

1. **Trait-based abstraction** - Enables compile-time optimization
2. **Platform modules** - Clear separation of platform code
3. **Capability detection** - Runtime feature availability checks
4. **Error mapping** - Platform errors mapped to common types
5. **Native performance** - Direct API calls, no wrappers

This architecture ensures Reaper can expand to multiple platforms while maintaining the performance characteristics critical for a system monitor.