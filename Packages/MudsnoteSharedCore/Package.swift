// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MudsnoteSharedCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "MudsnoteSharedCore", targets: ["MudsnoteSharedCore"])
    ],
    targets: [
        .target(
            name: "MudsnoteSharedCore",
            path: "Sources/MudsnoteSharedCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "MudsnoteSharedCoreTests",
            dependencies: ["MudsnoteSharedCore"],
            path: "Tests/MudsnoteSharedCoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
