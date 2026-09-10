// swift-tools-version: 6.0
import PackageDescription

// Benchmarks clean-up models in-process, the way the app would embed one.
// Links Homebrew's llama.cpp (`brew install llama.cpp`); run with run.sh.
let package = Package(
    name: "bench",
    platforms: [.macOS("26.0")],
    targets: [
        .systemLibrary(name: "CLlama", path: "Sources/CLlama"),
        .executableTarget(
            name: "bench",
            dependencies: ["CLlama"],
            path: "Sources/bench",
            swiftSettings: [.unsafeFlags(["-I/opt/homebrew/include"])],
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]), .linkedLibrary("llama")]
        ),
    ]
)
