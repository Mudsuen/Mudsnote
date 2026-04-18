// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mudsnote",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MudsnoteCore", targets: ["MudsnoteCore"]),
        .executable(name: "mudsnote", targets: ["Mudsnote"])
    ],
    targets: [
        .target(
            name: "MudsnoteCore",
            path: "Sources/MudsnoteCore"
        ),
        .executableTarget(
            name: "Mudsnote",
            dependencies: ["MudsnoteCore"],
            path: "Sources/Mudsnote"
        ),
        .testTarget(
            name: "MudsnoteCoreTests",
            dependencies: ["MudsnoteCore"],
            path: "Tests/MudsnoteCoreTests"
        ),
        .testTarget(
            name: "MudsnoteAppTests",
            dependencies: ["Mudsnote", "MudsnoteCore"],
            path: "Tests/MudsnoteAppTests"
        )
    ]
)
