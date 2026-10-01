// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FontCompare",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FontCompare",
            path: "Sources/FontCompare"
        )
    ]
)
