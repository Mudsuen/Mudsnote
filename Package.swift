// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Mudsnote",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "MudsnoteCore", targets: ["MudsnoteCore"]),
        .executable(name: "mudsnote", targets: ["Mudsnote"])
    ],
    dependencies: [
        .package(path: "Packages/MudsnoteSharedCore")
    ],
    targets: [
        .target(
            name: "MudsnoteCore",
            dependencies: [
                .product(name: "MudsnoteSharedCore", package: "MudsnoteSharedCore")
            ],
            path: "Sources/MudsnoteCore"
        ),
        .executableTarget(
            name: "Mudsnote",
            dependencies: [
                "MudsnoteCore",
                .product(name: "MudsnoteSharedCore", package: "MudsnoteSharedCore")
            ],
            path: "Sources/Mudsnote"
        ),
        .testTarget(
            name: "MudsnoteCoreTests",
            dependencies: [
                "MudsnoteCore",
                .product(name: "MudsnoteSharedCore", package: "MudsnoteSharedCore")
            ],
            path: "Tests/MudsnoteCoreTests"
        ),
        .testTarget(
            name: "MudsnoteAppTests",
            dependencies: [
                "Mudsnote",
                "MudsnoteCore",
                .product(name: "MudsnoteSharedCore", package: "MudsnoteSharedCore")
            ],
            path: "Tests/MudsnoteAppTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
