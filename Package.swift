// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FjordComputer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FjordComputer", path: "Sources/FjordComputer"),
        .testTarget(name: "FjordComputerTests", dependencies: ["FjordComputer"], path: "Tests/FjordComputerTests"),
    ]
)
