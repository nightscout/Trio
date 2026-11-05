// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarmonizeRules",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/perrystreetsoftware/Harmonize.git", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.1")
    ],
    targets: [
        .testTarget(
            name: "HarmonizeRulesTests",
            dependencies: [
                .product(name: "Harmonize", package: "Harmonize"),
                .product(name: "HarmonizeSemantics", package: "Harmonize"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        )
    ]
)
