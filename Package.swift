// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextMateSwift",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Core text engine: piece storage, indexed map, buffer, UTF-8, undo.
        .target(
            name: "TextCore",
            path: "Sources/TextCore"
        ),
        // Ported original-TextMate suites + engine unit tests.
        .testTarget(
            name: "TextCoreTests",
            dependencies: ["TextCore"],
            path: "Tests/TextCoreTests"
        ),
        // AppKit editor application (first buildable macOS app).
        .executableTarget(
            name: "TextMateSwift",
            dependencies: ["TextCore"],
            path: "Sources/TextMateSwift"
        ),
    ]
)
