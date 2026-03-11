// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChorographDotNetTestPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ChorographDotNetTestPlugin",
            type: .dynamic,
            targets: ["ChorographDotNetTestPlugin"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/aorgcorn/chorograph-plugin-sdk.git",
            from: "1.0.3"
        ),
    ],
    targets: [
        .target(
            name: "ChorographDotNetTestPlugin",
            dependencies: [
                .product(name: "ChorographPluginSDK", package: "chorograph-plugin-sdk"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"]),
            ]
        ),
    ]
)
