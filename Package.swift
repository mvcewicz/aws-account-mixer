// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AWSAccountMixer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AWSAccountMixer",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "AWSAccountMixerTests",
            dependencies: ["AWSAccountMixer"]
        ),
    ]
)
