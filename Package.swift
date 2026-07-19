// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Porthole",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Porthole",
            path: "Sources/Porthole"
        )
    ]
)
