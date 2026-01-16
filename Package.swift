// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceTranscriptor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceTranscriptor", targets: ["VoiceTranscriptor"])
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/whisper.spm", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceTranscriptor",
            dependencies: [
                .product(name: "whisper", package: "whisper.spm")
            ]
        ),
        .testTarget(
            name: "VoiceTranscriptorTests",
            dependencies: ["VoiceTranscriptor"]
        )
    ]
)
