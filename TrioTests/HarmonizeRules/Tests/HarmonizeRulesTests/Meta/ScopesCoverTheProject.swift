import Foundation
import Harmonize
import Testing

@Suite struct ScopesCoverTheProject {
    @Test func productionCodeIsTriosOwn() {
        TrioHarmonize.productionCode.sources().assertTrue(rule: Self.rule, strict: true) { file in
            Self.isTriosOwn(file.relativePath)
        }
    }

    @Test func testCodeIsTriosOwn() {
        TrioHarmonize.testCode.sources().assertTrue(rule: Self.rule, strict: true) { file in
            Self.testRoots.contains { file.relativePath.hasPrefix($0) }
        }
    }

    @Test func everyNamedScopeFindsFiles() {
        let scopes: [(name: String, scope: HarmonizeScope)] = [
            ("app", TrioHarmonize.app),
            ("coreDataModel", TrioHarmonize.coreDataModel),
            ("watchExtension", TrioHarmonize.watchExtension),
            ("liveActivity", TrioHarmonize.liveActivity),
            ("unitTests", TrioHarmonize.unitTests),
            ("watchTests", TrioHarmonize.watchTests)
        ]

        for (name, scope) in scopes {
            #expect(
                !scope.sources().isEmpty,
                "TrioHarmonize.\(name) finds no files: its folder moved, or .harmonize.yaml excludes it"
            )
        }
    }

    @Test func testScopesPartitionTheTestCode() {
        let all = TrioHarmonize.testCode.sources().count

        #expect(all == TrioHarmonize.unitTests.sources().count + TrioHarmonize.watchTests.sources().count)
    }

    @Test func theRulesDoNotLintThemselves() {
        let rules = (TrioHarmonize.productionCode.sources() + TrioHarmonize.testCode.sources())
            .filter { $0.relativePath.contains("HarmonizeRules/") }

        #expect(
            rules.isEmpty,
            "The rules package is in scope; keep HarmonizeRules in .harmonize.yaml's excludes:\n\(rules.map(\.relativePath).joined(separator: "\n"))"
        )
    }

    @Test func noFileIsFoundTwice() {
        let paths = (TrioHarmonize.productionCode.sources() + TrioHarmonize.testCode.sources()).map(\.relativePath)
        let duplicates = Dictionary(grouping: paths) { $0 }.filter { $0.value.count > 1 }.keys.sorted()

        #expect(
            duplicates.isEmpty,
            "Parsed more than once, through a symlink or an overlapping scope:\n\(duplicates.joined(separator: "\n"))"
        )
    }

    private static let sourceRoots = [
        "Trio/Sources/",
        "Model/",
        "Trio Watch App/",
        "Trio Watch App Extension/",
        "Trio Watch Complication/",
        "LiveActivity/"
    ]

    private static let testRoots = ["TrioTests/", "Trio Watch App Tests/"]

    private static func isTriosOwn(_ path: String) -> Bool {
        // The TDDStored Core Data pair sits directly at the root.
        !path.contains("/") || sourceRoots.contains { path.hasPrefix($0) }
    }

    private static let rule = Rule(
        description: "Harmonize's scopes cover Trio's own Swift sources and nothing else.",
        rationale: """
        .harmonize.yaml marks the project root and excludes the submodules, the tools packages and the shadow
        AlgorithmPackage, whose symlinks would parse every algorithm file twice. A directory added without an entry
        is linted as if it were Trio's code, and a scope that finds no files passes every rule vacuously.
        """,
        fixHint: "Add the directory to the excludes in .harmonize.yaml if the code is not Trio's, or to sourceRoots here if it is.",
        badExample: "// LoopKit/LoopKit/InsulinKit/DoseStore.swift reported by a Trio rule",
        goodExample: "excludes:\n  - LoopKit"
    )
}
