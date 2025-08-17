// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReaperApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ReaperApp",
            targets: ["ReaperApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ReaperApp",
            dependencies: [],
            linkerSettings: [
                .unsafeFlags([
                    "-L../target/release",
                    "-lreaper_core",
                    "-lreaper_cpu_monitor",
                    "-lreaper_memory_monitor",
                    "-lreaper_hardware_monitor",
                    "-lreaper_network_monitor",
                    "-framework", "Security",
                    "-framework", "CoreFoundation"
                ])
            ]
        )
    ]
)
