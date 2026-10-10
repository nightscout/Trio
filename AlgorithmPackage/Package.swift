// swift-tools-version:5.9
import PackageDescription

// Builds the oref algorithm as a standalone, Foundation-only module
// (`OrefAlgorithm`) so it can be consumed by other projects and so
// the algorithm test suite can run with `swift test`.
//
// This is a "shadow" package: it compiles the *existing* files in
// place rather than owning its own copy, so there is exactly one
// copy of every source file and the Xcode app target keeps
// compiling the same ones. `Sources` and `OpenAPSSwiftTests` are
// symlinks back to Trio/Sources and TrioTests/OpenAPSSwiftTests.
//
// Because the app target compiles these files directly, the `public`
// annotations on the generators and their input/output models cost
// the app nothing; they exist for consumers of this package.
//
// The module is named `OrefAlgorithm`, but the algorithm tests were
// written for the app module and say `@testable import Trio`. Rather
// than fork them, the test target passes `-module-alias
// Trio=OrefAlgorithm`, which makes the compiler read the name `Trio`
// as `OrefAlgorithm` while compiling that one target. The flag is per
// target and is not seen by anything that depends on this package, so
// consumers still `import OrefAlgorithm`. One rule follows: a source
// file in the aliased target may not spell `OrefAlgorithm` itself, not
// even in an inactive `#if` branch.
//
// `Example/` is the smallest possible consumer: an executable that does
// a plain `import OrefAlgorithm` and calls one public function. It and
// its test target carry no alias flag on purpose, so `swift test` fails
// if the public import path other projects use ever breaks.
//
// This lives in a subdirectory, not the repo root, because Xcode
// prefers a root Package.swift over Trio.xcworkspace when opening
// a folder — a root manifest makes `xed .` open the package and
// hides every app scheme. A consequence is that other projects
// depend on it by path, not by git URL:
//
//   .package(path: "../Trio/AlgorithmPackage")
//   .product(name: "OrefAlgorithm", package: "AlgorithmPackage")
//
// Usage:
//   swift build --package-path AlgorithmPackage
//   swift test --package-path AlgorithmPackage
//   swift test --package-path AlgorithmPackage --filter IobGenerateTests
//   swift run --package-path AlgorithmPackage OrefAlgorithmExample

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
    name: "OrefAlgorithm",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS("17.6")],
    products: [
        .library(name: "OrefAlgorithm", targets: ["OrefAlgorithm"])
    ],
    targets: [
        .target(
            name: "OrefAlgorithm",
            path: "Sources",
            // app-only resource bundles under the symlinked Sources tree; the new SwiftPM build
            // system would otherwise compile the app string catalog into this module
            exclude: ["AnimatedBackground", "Localizations"],
            sources: [
                "APS/OpenAPSSwift",
                "APS/Extensions/DecimalExtensions.swift"
            ] + algorithmModels + algorithmHelpers,
            swiftSettings: [.define("TRIO_ALGORITHM_PACKAGE")]
        ),
        .testTarget(
            name: "OpenAPSSwiftTests",
            dependencies: ["OrefAlgorithm"],
            path: "OpenAPSSwiftTests",
            // goldens are read from disk via #filePath, not from the test bundle
            exclude: ["Parity/goldens"],
            resources: [.copy("json")],
            swiftSettings: [.unsafeFlags(["-module-alias", "Trio=OrefAlgorithm"])]
        ),
        .executableTarget(
            name: "OrefAlgorithmExample",
            dependencies: ["OrefAlgorithm"],
            path: "Example"
        ),
        .testTarget(
            name: "OrefAlgorithmExampleTests",
            dependencies: ["OrefAlgorithmExample"],
            path: "ExampleTests"
        )
    ]
)
