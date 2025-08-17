# Reaper 💀

> Advanced System Monitor for macOS with Unkillable Process Detection

[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![Rust](https://img.shields.io/badge/Rust-1.75-red.svg)](https://www.rust-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 🎯 Overview

Reaper is a powerful system monitoring application for macOS that goes beyond traditional activity monitors. Built with a Rust backend for performance and a native SwiftUI interface, it specializes in detecting and analyzing problematic processes that resist termination.

## ✨ Features

### Current (v0.2.0)
- 📊 **Real-time Process Monitoring** - CPU, memory, and resource usage
- 🔍 **Advanced Process Detection** - Identify unkillable and zombie processes
- 📈 **System Metrics** - Load average, CPU cores, frequency monitoring
- 🎨 **Native SwiftUI Interface** - Beautiful, responsive macOS app
- ⚡ **High Performance** - Rust backend with minimal system impact
- ✅ **Process Management** - Terminate, kill, suspend, and resume processes
- 🔔 **Smart Notifications** - Visual feedback for all actions
- ⌨️ **Keyboard Shortcuts** - Full keyboard control for power users
- 💾 **Persistent Preferences** - Remember your settings between sessions
- 🛡️ **Safety First** - Confirmation dialogs for destructive actions

### Coming Soon
- 🔄 Column resizing and reordering
- 📦 Batch process operations
- 💾 Memory, disk, and network monitors
- 🚨 Configurable alerts and automation
- 🔍 Advanced process analysis (deadlocks, I/O wait)
- 📊 Historical performance graphs

See [ROADMAP.md](ROADMAP.md) for the complete development plan.

## 🚀 Quick Start

### Prerequisites
- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools
- Rust toolchain (1.75+)
- Swift 5.9+

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/Reaper.git
cd Reaper
```

2. Build the application:
```bash
./build_app_bundle.sh
```

3. Run Reaper:
```bash
open Reaper.app
```

### Development Build

For development with hot reload:
```bash
# Build Rust libraries
cargo build --release

# Build and run Swift app
cd ReaperApp
swift run
```

## 🏗 Architecture

```
Reaper/
├── core/              # Shared Rust library
├── monitors/          # System monitors (CPU, Memory, Disk, Network)
│   └── cpu/          # CPU monitor implementation
├── ReaperApp/        # SwiftUI application
└── Reaper.app/       # Built application bundle
```

### Technology Stack
- **Backend**: Rust with FFI bridge
- **Frontend**: SwiftUI with Combine
- **IPC**: Direct FFI for performance
- **Build**: Cargo + Swift Package Manager

## 🔧 Configuration

Reaper runs with default settings out of the box. Advanced configuration coming in v0.2.0.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Building from Source

```bash
# Install dependencies
brew install rust

# Build everything
make all

# Run tests
make test

# Clean build artifacts
make clean
```

## 📋 Requirements

### System Requirements
- **OS**: macOS 13.0+
- **Memory**: 512MB RAM minimum
- **Disk**: 50MB free space
- **Processor**: Apple Silicon or Intel

### Permissions
Reaper may request the following permissions:
- Full Disk Access (for complete process information)
- Accessibility (for global shortcuts)

## 🐛 Known Issues

- NSTableView reentrant warning (fixed in latest)
- Requires manual app bundle creation for UI
- Some kernel processes show limited information

## 📊 Performance

- **CPU Usage**: < 2% idle, < 5% active monitoring
- **Memory**: ~50MB base footprint
- **Update Rate**: 1Hz default (configurable)

## 🔒 Security

Reaper is designed with security in mind:
- No network connections without user consent
- No data collection or telemetry
- Local processing only
- Code signed and notarized (coming soon)

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [sysinfo](https://github.com/GuillaumeGomez/sysinfo) - System information library
- [mach2](https://github.com/JohnTitor/mach2) - Mach kernel interface
- Apple's SwiftUI framework

## 📧 Contact

- Report bugs: [Issues](https://github.com/yourusername/Reaper/issues)
- Email: reaper@yourdomain.com
- Twitter: [@ReaperApp](https://twitter.com/ReaperApp)

## 🗺 Roadmap

See [ROADMAP.md](ROADMAP.md) for detailed development plans.

### Next Release (v0.2.0)
- ✅ Context menu for process management
- ✅ Column sorting
- ✅ Keyboard shortcuts
- ✅ Process detail view
- ⏳ Memory monitor

---

**Built with ❤️ and ⚡ by the Reaper Team**

*Reaper - When processes refuse to die* 💀