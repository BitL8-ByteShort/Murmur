// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Murmur", targets: ["Murmur"]),
        .library(name: "MurmurCore", targets: ["MurmurCore"])
    ],
    targets: [
        .target(name: "MurmurCore"),
        .executableTarget(name: "Murmur", dependencies: ["MurmurCore"]),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
        .testTarget(name: "MurmurAppTests", dependencies: ["Murmur", "MurmurCore"])
    ]
)
