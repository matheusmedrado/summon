// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Summon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Summon",
            path: "Sources/Summon",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
