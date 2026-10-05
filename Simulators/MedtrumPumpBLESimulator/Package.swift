// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MedtrumPumpBLESimulator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MedtrumSimulatorProtocol", targets: ["MedtrumSimulatorProtocol"]),
        .executable(name: "MedtrumPumpBLESimulator", targets: ["MedtrumPumpBLESimulator"]),
        .executable(name: "MedtrumProtocolChecks", targets: ["MedtrumProtocolChecks"])
    ],
    targets: [
        .target(name: "MedtrumSimulatorProtocol"),
        .executableTarget(
            name: "MedtrumPumpBLESimulator",
            dependencies: ["MedtrumSimulatorProtocol"],
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "MedtrumProtocolChecks",
            dependencies: ["MedtrumSimulatorProtocol"]
        ),
        .testTarget(
            name: "MedtrumSimulatorProtocolTests",
            dependencies: ["MedtrumSimulatorProtocol"]
        )
    ],
    swiftLanguageModes: [.v5]
)
