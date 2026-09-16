// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacVolumeMixer",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "MacVolumeMixer", targets: ["MacVolumeMixer"]),
    ],
    targets: [
        .target(name: "RealtimeAtomics"),
        .target(name: "MixerCore", dependencies: ["RealtimeAtomics"]),
        .target(name: "AudioHAL", dependencies: ["MixerCore", "RealtimeAtomics"]),
        .executableTarget(name: "MacVolumeMixer", dependencies: ["MixerCore", "AudioHAL"]),
        .testTarget(name: "MixerCoreTests", dependencies: ["MixerCore"]),
    ]
)
