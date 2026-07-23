// swift-tools-version:5.9
import PackageDescription

// Standalone, dependency-free package for CGM glucose smoothing algorithms — kept out of the app
// target so the numeric core is unit-testable with `swift test` alone (mirrors how BoostV5Core is
// structured on the Boost branch). P0 ships the Unscented Kalman Filter smoother + golden vectors;
// app wiring (Seam 1 in FetchGlucoseManager) lands in a later phase.
let package = Package(
    name: "GlucoseSmoothingCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "GlucoseSmoothingCore", targets: ["GlucoseSmoothingCore"])
    ],
    targets: [
        .target(name: "GlucoseSmoothingCore"),
        .testTarget(
            name: "GlucoseSmoothingCoreTests",
            dependencies: ["GlucoseSmoothingCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
