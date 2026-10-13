// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FjordComputer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FjordComputer", path: "Sources/FjordComputer", linkerSettings: [
            // AppKit reads this before the first text input, including when tooling runs the bare SwiftPM executable.
            .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                          "-Xlinker", Context.packageDirectory + "/Resources/AppInfo.plist"]),
        ]),
        .testTarget(name: "FjordComputerTests", dependencies: ["FjordComputer"], path: "Tests/FjordComputerTests"),
    ]
)
