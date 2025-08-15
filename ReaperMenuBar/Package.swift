// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ReaperMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ReaperMenuBar",
            targets: ["ReaperMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ReaperMenuBar",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags([
                    "-L../target/release",
                    "-lreaper_cpu_monitor",
                    "-framework", "IOKit",
                    "-framework", "CoreFoundation"
                ])
            ]
        )
    ]
)