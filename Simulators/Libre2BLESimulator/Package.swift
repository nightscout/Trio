// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Libre2BLESimulator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Libre2Protocol", targets: ["Libre2Protocol"]),
        .executable(name: "Libre2BLESimulator", targets: ["Libre2BLESimulator"])
    ],
    targets: [
        .target(name: "Libre2Protocol"),
        .executableTarget(
            name: "Libre2BLESimulator",
            dependencies: ["Libre2Protocol"]
        ),
        .testTarget(
            name: "Libre2ProtocolTests",
            dependencies: ["Libre2Protocol"]
        )
    ]
)
