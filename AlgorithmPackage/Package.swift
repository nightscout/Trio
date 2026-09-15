// swift-tools-version:5.9
import PackageDescription

// Builds the oref algorithm as a standalone, macOS-capable module
// so the algorithm test suite can run with `swift test`
//
// This is a "shadow" package: it compiles the *existing* files in
// place rather than owning its own copy, so there is exactly one
// copy of every source file and the Xcode app target keeps
// compiling the same ones. `Sources` and `OpenAPSSwiftTests` are
// symlinks back to Trio/Sources and TrioTests/OpenAPSSwiftTests.
//
// This lives in a subdirectory, not the repo root, because Xcode
// prefers a root Package.swift over Trio.xcworkspace when opening
// a folder — a root manifest makes `xed .` open the package and
// hides every app scheme.
//
// Usage:
//   swift test --package-path AlgorithmPackage
//   swift test --package-path AlgorithmPackage --filter IobGenerateTests

let algorithmModels = [
    "Autosens",
    "BGTargets",
    "BasalProfileEntry",
    "BloodGlucose",
    "CarbRatios",
    "CarbsEntry",
    "Determination",
    "IOBEntry",
    "InsulinSensitivities",
    "Override",
    "Preferences",
    "PumpHistoryEvent",
    "PumpSettings",
    "TDD",
    "TempBasal",
    "TempTarget",
    "TrioCustomOrefVariables"
].map { "Models/\($0).swift" }

let algorithmHelpers = [
    "ConvenienceExtensions",
    "Decimal+Extensions",
    "Formatters",
    "JSON",
    "Rounding",
    "String+Extensions",
    "TherapySettingsUtil",
    "TimeInterval+Convenience"
].map { "Helpers/\($0).swift" }

let package = Package(
    name: "TrioAlgorithm",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Trio", targets: ["Trio"])
    ],
    targets: [
        .target(
            name: "Trio",
            path: "Sources",
            sources: [
                "APS/OpenAPSSwift",
                "APS/Extensions/DecimalExtensions.swift"
            ] + algorithmModels + algorithmHelpers,
            swiftSettings: [.define("TRIO_ALGORITHM_PACKAGE")]
        ),
        .testTarget(
            name: "OpenAPSSwiftTests",
            dependencies: ["Trio"],
            path: "OpenAPSSwiftTests",
            // goldens are read from disk via #filePath, not from the test bundle
            exclude: ["Parity/goldens"],
            resources: [.copy("json")],
            swiftSettings: [.define("TRIO_ALGORITHM_PACKAGE")]
        )
    ]
)
