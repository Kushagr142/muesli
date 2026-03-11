// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MuesliNative",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "MuesliNativeApp", targets: ["MuesliNativeApp"]),
    ],
    targets: [
        .executableTarget(
            name: "MuesliNativeApp",
            path: "Sources/MuesliNativeApp"
        ),
    ]
)
