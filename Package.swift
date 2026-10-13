// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Fjord",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Fjord", path: "Sources/Fjord", linkerSettings: [
            // AppKit reads this before the first text input, including when tooling runs the bare SwiftPM executable.
            .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                          "-Xlinker", Context.packageDirectory + "/Resources/AppInfo.plist"]),
        ]),
        .testTarget(name: "FjordTests", dependencies: ["Fjord"], path: "Tests/FjordTests"),
    ]
)
