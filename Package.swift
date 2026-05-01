// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/johnxnguyen/Down.git", from: "0.11.0"),
        .package(url: "https://github.com/typelift/SwiftCheck.git", .upToNextMajor(from: "0.12.0"))
    ],
    targets: [
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: ["Down", "MarkdownEditorCore"],
            path: "Sources/MarkdownEditor",
            resources: [
                .process("Resources")
            ]
        ),
        // 可测试的核心库：包含 MarkdownSyntaxHighlighter 和 MarkdownStyleTokens
        .target(
            name: "MarkdownEditorCore",
            path: "Sources/MarkdownEditorCore"
        ),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: [
                "MarkdownEditorCore",
                .product(name: "SwiftCheck", package: "SwiftCheck")
            ],
            path: "Tests/MarkdownEditorTests"
        )
    ]
)
