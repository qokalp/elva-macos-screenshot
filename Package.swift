// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Elva",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Elva",
            path: "Sources/Elva"
        )
    ]
)
