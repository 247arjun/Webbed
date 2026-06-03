// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WebbedKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "WebbedKit", targets: ["WebbedKit"]),
    ],
    targets: [
        .target(
            name: "WebbedKit",
            path: "Sources/WebbedKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
