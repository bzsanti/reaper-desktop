// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReaperApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ReaperApp",
            targets: ["ReaperApp"]
        )
    ],
    dependencies: [
        .package(path: "../ReaperShared"),
    ],
    targets: [
        .executableTarget(
            name: "ReaperApp",
            dependencies: ["ReaperShared"],
            linkerSettings: [
                .unsafeFlags([
                    "-L../target/release",
                    "-lreaper_core",
                    "-lreaper_cpu_monitor",
                    "-lreaper_memory_monitor",
                    "-lreaper_hardware_monitor",
                    "-lreaper_network_monitor",
                    "-lreaper_disk_monitor",
                    "-framework", "Security",
                    "-framework", "CoreFoundation",
                    "-framework", "IOKit"
                ])
            ]
        )
    ]
)
