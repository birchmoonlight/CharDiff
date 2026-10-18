// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CharDiff",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CharDiff",
            path: "Sources/CharDiff"
        )
    ]
)
