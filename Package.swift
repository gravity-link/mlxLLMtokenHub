// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mlxLLM",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "MLXMeshCore", targets: ["MLXMeshCore"]),
        .library(name: "MLXMeshNetworking", targets: ["MLXMeshNetworking"]),
        .library(name: "MLXMeshEngine", targets: ["MLXMeshEngine"]),
        .library(name: "MLXMeshApp", targets: ["MLXMeshApp"]),
        .executable(name: "mlxmesh-cli", targets: ["MLXMeshCLI"])
    ],
    dependencies: [
        // MLX Swift bindings for Apple Silicon neural network operations
        // Can be resolved when building with full internet access to GitHub
    ],
    targets: [
        .target(
            name: "MLXMeshCore",
            dependencies: [],
            path: "Sources/MLXMeshCore"
        ),
        .target(
            name: "MLXMeshNetworking",
            dependencies: ["MLXMeshCore"],
            path: "Sources/MLXMeshNetworking"
        ),
        .target(
            name: "MLXMeshEngine",
            dependencies: ["MLXMeshCore", "MLXMeshNetworking"],
            path: "Sources/MLXMeshEngine"
        ),
        .target(
            name: "MLXMeshApp",
            dependencies: ["MLXMeshCore", "MLXMeshNetworking", "MLXMeshEngine"],
            path: "Sources/MLXMeshApp"
        ),
        .executableTarget(
            name: "MLXMeshCLI",
            dependencies: ["MLXMeshCore", "MLXMeshNetworking", "MLXMeshEngine"],
            path: "Sources/MLXMeshCLI"
        ),
        .testTarget(
            name: "MLXMeshTests",
            dependencies: ["MLXMeshCore", "MLXMeshNetworking", "MLXMeshEngine"],
            path: "Tests/MLXMeshTests"
        )
    ]
)
