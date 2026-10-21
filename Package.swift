// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuMeter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MenuMeterCore", targets: ["MenuMeterCore"]),
        .executable(name: "MenuMeter", targets: ["MenuMeter"]),
    ],
    targets: [
        .target(
            name: "MenuMeterCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "MenuMeter",
            dependencies: ["MenuMeterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "MenuMeterCoreTests",
            dependencies: ["MenuMeterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
