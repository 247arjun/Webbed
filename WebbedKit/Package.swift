// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebbedKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
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
