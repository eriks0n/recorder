// swift-tools-version:6.0
import PackageDescription
import Foundation

// The full app includes local summaries. RECORDER_WITH_MLX=0 explicitly builds the transcription-only variant.
let withMLX = ProcessInfo.processInfo.environment["RECORDER_WITH_MLX"] != "0"
let mlxPackages: [Package.Dependency] = withMLX ? [.package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "2.29.3")] : []
let mlxProducts: [Target.Dependency] = withMLX ? [.product(name: "MLXLLM", package: "mlx-swift-lm"), .product(name: "MLXLMCommon", package: "mlx-swift-lm")] : []

let package = Package(
    name: "Recorder",
    platforms: [
        // macOS 15+: the Synchronization module's `Atomic` (used by the
        // realtime-safe ring buffer in the system-audio tap) requires it.
        .macOS("15")
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0")
    ] + mlxPackages,
    targets: [
        .executableTarget(
            name: "Recorder",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "SpeakerKit", package: "WhisperKit")
            ] + mlxProducts,
            path: "Sources/Recorder",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(name: "RecorderTests", dependencies: ["Recorder"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
