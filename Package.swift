// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/johnxnguyen/Down.git", from: "0.11.0")
    ],
    targets: [
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: ["Down"],
            path: "Sources/MarkdownEditor",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
