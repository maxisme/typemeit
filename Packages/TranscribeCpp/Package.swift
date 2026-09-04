// swift-tools-version: 5.9
import PackageDescription

// transcribe.cpp ships a prebuilt XCFramework with every release. The module
// map inside it exposes the C API as `CTranscribe`; this package re-exports it
// and carries the system libraries and frameworks the static archive needs.
let package = Package(
    name: "TranscribeCpp",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TranscribeCpp", targets: ["TranscribeCpp"])],
    targets: [
        .binaryTarget(
            name: "CTranscribe",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.2.3/TranscribeCpp.xcframework.zip",
            checksum: "944be4d5232f39c99608f676a2ddda2516e0ed3c9fb6db50685ffa8d20a8b9c9"
        ),
        .target(
            name: "TranscribeCpp",
            dependencies: ["CTranscribe"],
            path: "Sources/TranscribeCpp",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
    ]
)
