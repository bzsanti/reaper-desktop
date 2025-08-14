// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CPUMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CPUMonitor",
            targets: ["CPUMonitorApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CPUMonitorApp",
            dependencies: [],
            path: "swift-ui/Sources/CPUMonitorApp",
            linkerSettings: [
                .unsafeFlags([
                    "-L./target/release",
                    "-lcpu_monitor_core",
                    "-framework", "Security",
                    "-framework", "CoreFoundation"
                ])
            ]
        )
    ]
)