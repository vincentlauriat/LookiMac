// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LookiKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LookiKit", targets: ["LookiKit"]),
    ],
    targets: [
        .target(
            name: "LookiKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LookiKitTests",
            dependencies: ["LookiKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
