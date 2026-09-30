// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "iDump",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "iDump", path: "Sources/iDump")
    ]
)
