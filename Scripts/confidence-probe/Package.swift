// swift-tools-version: 5.9
import PackageDescription

// Reads per-word confidence from the app's own Transcriber over the
// recordings kept in history, to see whether misheard words score low.
// Transcriber.swift and Log.swift are symlinked in; run with run.sh.
let package = Package(
    name: "probe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/TranscribeCpp")],
    targets: [
        .executableTarget(name: "probe", dependencies: ["TranscribeCpp"], path: "Sources/probe"),
    ]
)
