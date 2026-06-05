// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotesTool",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotesTool",
            path: "Sources/NotesTool"
        )
    ]
)
