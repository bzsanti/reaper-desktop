// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ReaperMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ReaperMenuBar",
            targets: ["ReaperMenuBar"]
        )
    ],
    dependencies: [
        .package(path: "../ReaperShared"),
    ],
    targets: [
        .executableTarget(
            name: "ReaperMenuBar",
            dependencies: ["ReaperShared"],
            path: "Sources",
            linkerSettings: [
                .unsafeFlags([
                    "-L../target/release",
                    "-lreaper_cpu_monitor",
                    "-lreaper_disk_monitor",
                    "-framework", "IOKit",
                    "-framework", "CoreFoundation"
                ])
            ]
        )
    ]
)