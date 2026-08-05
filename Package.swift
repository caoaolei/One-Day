// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YiRi",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "YiRi", targets: ["YiRiApp"])
    ],
    targets: [
        .executableTarget(
            name: "YiRiApp",
            path: "Sources/YiRiApp"
        )
    ]
)
