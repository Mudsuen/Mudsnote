// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickMarkdown",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "QuickMarkdownCore", targets: ["QuickMarkdownCore"]),
        .executable(name: "quickmarkdown", targets: ["QuickMarkdown"])
    ],
    targets: [
        .target(
            name: "QuickMarkdownCore",
            path: "Sources/QuickMarkdownCore"
        ),
        .executableTarget(
            name: "QuickMarkdown",
            dependencies: ["QuickMarkdownCore"],
            path: "Sources/QuickMarkdown"
        ),
        .testTarget(
            name: "QuickMarkdownCoreTests",
            dependencies: ["QuickMarkdownCore"],
            path: "Tests/QuickMarkdownCoreTests"
        ),
        .testTarget(
            name: "QuickMarkdownAppTests",
            dependencies: ["QuickMarkdown", "QuickMarkdownCore"],
            path: "Tests/QuickMarkdownAppTests"
        )
    ]
)
