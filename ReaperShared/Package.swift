// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReaperShared",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Core library without FFI dependencies
        .library(
            name: "ReaperShared",
            targets: ["ReaperShared"]
        ),
    ],
    targets: [
        // Core target: Types, protocols, and abstractions
        // Does NOT include RustMetricsProvider (which requires FFI)
        .target(
            name: "ReaperShared",
            path: "Sources",
            exclude: ["RustMetricsProvider.swift"]
        ),
        // Tests for the core functionality
        .testTarget(
            name: "ReaperSharedTests",
            dependencies: ["ReaperShared"],
            path: "Tests",
            exclude: ["RustMetricsProviderTests.swift"]
        ),
    ]
)

// Note: RustMetricsProvider.swift is excluded from the package because it requires
// the Rust FFI libraries to be linked. It should be included directly in the app
// targets (ReaperApp, ReaperMenuBar, ReaperMetricsService) where the Rust libraries
// are available.
//
// To use RustMetricsProvider in your app:
// 1. Build Rust libraries: cd monitors && cargo build --release
// 2. Copy libreaper_cpu_monitor.dylib and libreaper_disk_monitor.dylib to app bundle
// 3. Include RustMetricsProvider.swift directly in your app target
