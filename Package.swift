// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Murmur", targets: ["Murmur"]),
        .library(name: "MurmurCore", targets: ["MurmurCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4"),
        .package(url: "https://github.com/moonshine-ai/moonshine-swift.git", exact: "0.1.5"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0")
    ],
    targets: [
        .target(name: "MurmurCore"),
        .executableTarget(name: "Murmur", dependencies: ["MurmurCore",
            .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "MoonshineVoice", package: "moonshine-swift"),
            .product(name: "WhisperKit", package: "argmax-oss-swift")], resources: [.copy("Licenses")]),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
        .testTarget(name: "MurmurAppTests", dependencies: ["Murmur", "MurmurCore"])
    ]
)
