// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MENACEForMacOS",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "menace-macos", targets: ["MENACECLI"])
    ],
    targets: [
        .target(name: "MENACEBuilder"),
        .executableTarget(
            name: "MENACECLI",
            dependencies: ["MENACEBuilder"]
        ),
        .testTarget(
            name: "MENACEBuilderTests",
            dependencies: ["MENACEBuilder"]
        )
    ]
)
