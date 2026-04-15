// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIVoice",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AIVoice",
            path: "Sources"
        ),
        .testTarget(
            name: "AIVoiceTests",
            dependencies: ["AIVoice"],
            path: "Tests"
        )
    ]
)
