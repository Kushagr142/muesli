// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MuesliNative",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "MuesliNativeApp", targets: ["MuesliNativeApp"]),
        .executable(name: "MuesliSystemAudio", targets: ["MuesliSystemAudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.16.0"),
    ],
    targets: [
        .executableTarget(
            name: "MuesliNativeApp",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/MuesliNativeApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "MuesliSystemAudio",
            path: "Sources/MuesliSystemAudio"
        ),
    ]
)
