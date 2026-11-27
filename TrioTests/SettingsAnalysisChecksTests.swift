import Foundation
import Testing
@testable import Trio

@Suite("Settings Analysis Checks Tests") struct SettingsAnalysisChecksTests {
    typealias Snapshot = SettingsAnalysis.SettingsSnapshot

    private func catalog() throws -> SettingsAnalysis.Catalog {
        try SettingsAnalysis.Catalog.loadBundled()
    }

    private func run(_ snapshot: Snapshot) throws -> SettingsAnalysis.SettingsCheckReport {
        SettingsAnalysis.SettingsChecks.run(snapshot: snapshot, catalog: try catalog())
    }

    private func outcome(_ id: String, in report: SettingsAnalysis.SettingsCheckReport) -> SettingsAnalysis.CheckOutcome? {
        report.results.first { $0.rule.id == id }?.outcome
    }

    private func isFlagged(_ id: String, in report: SettingsAnalysis.SettingsCheckReport) -> Bool {
        report.flagged.contains { $0.rule.id == id }
    }

    // MARK: Catalog integrity

    @Test("Bundled catalog decodes with unique rule IDs") func testCatalogDecodes() throws {
        let catalog = try catalog()
        #expect(!catalog.rules.isEmpty)
        #expect(Set(catalog.rules.map(\.id)).count == catalog.rules.count)
    }

    @Test("Every current settings check has an evaluator") func testEvaluatorsCoverCatalog() throws {
        let ids = try catalog().rules.filter { $0.kind == .settingsCheck && $0.status == .current }.map(\.id)
        for id in ids {
            #expect(SettingsAnalysis.SettingsChecks.evaluators[id] != nil, "No evaluator for \(id)")
        }
    }

    @Test("Every guard a rule references exists") func testReferencedGuardsExist() throws {
        let catalog = try catalog()
        for rule in catalog.rules {
            for id in rule.guards {
                #expect(catalog.guard(id) != nil, "\(rule.id) references unknown guard \(id)")
            }
        }
    }

    @Test("Advice text gives no amounts") func testAdviceHasNoAmounts() throws {
        let pattern = /(\d +\ s *%|\ d + (\.\d+)? \ s * U \/ h | by \d)/
        for rule in try catalog().rules {
            #expect(rule.advice.firstMatch(of: pattern) == nil, "\(rule.id) advice contains an amount")
        }
    }

    // MARK: Evaluation

    @Test("Recommended defaults flag nothing") func testDefaultsPass() throws {
        let report = try run(.defaults)
        #expect(report.flagged.isEmpty)
        #expect(report.startHere == nil)
    }

    @Test("DIA under 8 h is flagged and comes first") func testShortDIA() throws {
        var snapshot = Snapshot.defaults
        snapshot.dia = 6
        snapshot.weightPercentage = 0.65
        let report = try run(snapshot)
        #expect(isFlagged("I05", in: report))
        #expect(isFlagged("G06", in: report))
        #expect(report.startHere?.rule.id == "I05")
    }

    @Test("Max IOB 0 is only flagged in Closed Loop") func testMaxIOB() throws {
        var snapshot = Snapshot.defaults
        snapshot.maxIOB = 0
        #expect(try isFlagged("M06", in: run(snapshot)))

        snapshot.dosingMode = .open
        guard case .notApplicable = try outcome("M06", in: run(snapshot)) else {
            Issue.record("M06 should not apply outside Closed Loop")
            return
        }
    }

    @Test("SMB ratio and max rise are flagged when changed") func testSMBLimits() throws {
        var snapshot = Snapshot.defaults
        snapshot.smbDeliveryRatio = 0.7
        snapshot.maxDeltaBGThreshold = 0.1
        let report = try run(snapshot)
        #expect(isFlagged("M04", in: report))
        #expect(isFlagged("M05", in: report))

        snapshot.maxDeltaBGThreshold = 0.3
        #expect(try !isFlagged("M05", in: run(snapshot)))
    }

    @Test("Logarithmic mode flags G08 and skips sigmoid-only rules") func testLogarithmic() throws {
        var snapshot = Snapshot.defaults
        snapshot.dynamicISF = .logarithmic
        snapshot.adjustmentFactorSigmoid = 1.5
        let report = try run(snapshot)
        #expect(isFlagged("G08", in: report))
        guard case .notApplicable = outcome("S04", in: report) else {
            Issue.record("S04 should not apply with logarithmic Dynamic ISF")
            return
        }
    }

    @Test("Sigmoid Adjustment Factor above 100% is flagged") func testSigmoidAF() throws {
        var snapshot = Snapshot.defaults
        snapshot.adjustmentFactorSigmoid = 1.2
        #expect(try isFlagged("S04", in: run(snapshot)))
    }

    @Test("Dynamic ISF rules don't apply when Dynamic ISF is off") func testDynamicISFOff() throws {
        var snapshot = Snapshot.defaults
        snapshot.dynamicISF = .off
        snapshot.weightPercentage = 0.65
        snapshot.tddHistoryDays = nil
        let report = try run(snapshot)
        #expect(!isFlagged("G06", in: report))
        #expect(!isFlagged("G07", in: report))
    }

    @Test("Less than 7 days of TDD history is flagged") func testTDDHistory() throws {
        var snapshot = Snapshot.defaults
        snapshot.tddHistoryDays = nil
        #expect(try isFlagged("G07", in: run(snapshot)))
        snapshot.tddHistoryDays = 3
        #expect(try isFlagged("G07", in: run(snapshot)))
        snapshot.tddHistoryDays = 10
        #expect(try !isFlagged("G07", in: run(snapshot)))
    }

    // MARK: Guards

    @Test("P9 lowers pattern confidence when DIA is under 8 h") func testGuardP9() {
        var snapshot = Snapshot.defaults
        #expect(SettingsAnalysis.PatternGuards.effect(for: snapshot) == .init())

        snapshot.dia = 6
        let effect = SettingsAnalysis.PatternGuards.effect(for: snapshot)
        #expect(effect.confidenceAdjustment == -1)
        #expect(effect.guardIDs == ["P9"])
    }
}
