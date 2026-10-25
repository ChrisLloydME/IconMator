// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IconMator",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "IconConversionCore", targets: ["IconConversionCore"]),
        .executable(name: "iconmator", targets: ["iconmator"])
    ],
    targets: [
        .target(name: "IconConversionCore"),
        .executableTarget(name: "iconmator", dependencies: ["IconConversionCore"]),
        .testTarget(name: "IconConversionCoreTests", dependencies: ["IconConversionCore"])
    ]
)
