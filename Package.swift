// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "Vio",
    platforms: [.macOS("26.0")],
    targets: [
        .systemLibrary(
            name: "CNeedle",
            path: "Vendor/CNeedle"
        ),
        .executableTarget(
            name: "Vio",
            dependencies: ["CNeedle"],
            path: "Sources/Vio",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-L\(packageRoot)/Vendor/lib"]),
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "VioTests",
            dependencies: ["Vio"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
