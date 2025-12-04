// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReaperMetricsService",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ReaperMetricsService",
            targets: ["ReaperMetricsService"]
        ),
    ],
    dependencies: [
        .package(path: "../ReaperShared"),
    ],
    targets: [
        .executableTarget(
            name: "ReaperMetricsService",
            dependencies: ["ReaperShared"],
            path: "Sources",
            linkerSettings: [
                // Link Rust FFI libraries for production
                .unsafeFlags([
                    "-L../target/release",
                    "-lreaper_cpu_monitor",
                    "-lreaper_disk_monitor",
                    "-framework", "IOKit",
                    "-framework", "CoreFoundation"
                ])
            ]
        ),
        .testTarget(
            name: "ReaperMetricsServiceTests",
            dependencies: ["ReaperMetricsService", "ReaperShared"],
            path: "Tests"
        ),
    ]
)
