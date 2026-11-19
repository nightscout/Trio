import Foundation

// MARK: - Settings snapshot

extension SettingsAnalysis {
    enum DynamicISFMode: String, Hashable {
        case off
        case logarithmic
        case sigmoid

        var displayName: String {
            switch self {
            case .off: return String(localized: "Off")
            case .logarithmic: return String(localized: "Logarithmic")
            case .sigmoid: return String(localized: "Sigmoid")
            }
        }
    }

    /// Current settings only; changes within the analyzed time frame are not known.
    struct SettingsSnapshot: Equatable {
        var dosingMode: DosingMode
        /// Duration of insulin action in hours.
        var dia: Decimal
        var maxIOB: Decimal
        var smbDeliveryRatio: Decimal
        /// Fraction, e.g. 0.2 = 20%.
        var maxDeltaBGThreshold: Decimal
        var dynamicISF: DynamicISFMode
        /// Fraction, e.g. 0.5 = 50%.
        var adjustmentFactorSigmoid: Decimal
        var autosensMax: Decimal
        /// Fraction, e.g. 0.35 = 35%.
        var weightPercentage: Decimal
        /// Days since the oldest stored TDD, or nil if there is none.
        var tddHistoryDays: Double?

        static let defaults = SettingsSnapshot(
            dosingMode: .closed,
            dia: 10,
            maxIOB: 10,
            smbDeliveryRatio: 0.5,
            maxDeltaBGThreshold: 0.2,
            dynamicISF: .sigmoid,
            adjustmentFactorSigmoid: 0.5,
            autosensMax: 1.2,
            weightPercentage: 0.35,
            tddHistoryDays: 30
        )
    }
}

// MARK: - Check results

extension SettingsAnalysis {
    enum CheckOutcome: Equatable {
        /// The rule fires. `observed` describes the current value.
        case flagged(observed: String)
        case passed(observed: String)
        /// The rule does not apply to this configuration.
        case notApplicable(reason: String)
    }

    struct CheckResult: Identifiable {
        var id: String { rule.id }
        let rule: Rule
        let outcome: CheckOutcome

        var isFlagged: Bool {
            if case .flagged = outcome { return true }
            return false
        }
    }

    struct SettingsCheckReport {
        let catalogVersion: String
        let snapshot: SettingsSnapshot
        let results: [CheckResult]

        var flagged: [CheckResult] { results.filter(\.isFlagged) }
        var passed: [CheckResult] { results.filter { if case .passed = $0.outcome { return true } else { return false } } }

        /// Flagged checks after "Start Here", then passed ones, then ones that don't apply.
        var listed: [CheckResult] {
            Array(flagged.dropFirst()) + passed + results.filter {
                if case .notApplicable = $0.outcome { return true } else { return false }
            }
        }

        /// Guards P1 + P3: a single suggested first step, the flagged rule with the lowest priority.
        var startHere: CheckResult? { flagged.first }
    }
}

// MARK: - Engine

extension SettingsAnalysis {
    enum SettingsChecks {
        typealias Evaluator = (SettingsSnapshot) -> CheckOutcome

        /// Swift logic per catalog rule ID. A catalog rule without an evaluator is not run.
        static let evaluators: [String: Evaluator] = [
            "I05": { s in
                let observed = String(localized: "DIA \(s.dia.formatted()) h")
                return s.dia < 8 ? .flagged(observed: observed) : .passed(observed: observed)
            },
            "M06": { s in
                guard s.dosingMode == .closed else {
                    return .notApplicable(reason: String(localized: "Only checked in Closed Loop."))
                }
                let observed = String(localized: "Max IOB \(s.maxIOB.formatted()) U")
                return s.maxIOB == 0 ? .flagged(observed: observed) : .passed(observed: observed)
            },
            "M04": { s in
                let observed = String(localized: "Ratio \(s.smbDeliveryRatio.formatted())")
                return s.smbDeliveryRatio != 0.5 ? .flagged(observed: observed) : .passed(observed: observed)
            },
            "M05": { s in
                let observed = s.maxDeltaBGThreshold.formatted(.percent)
                return s.maxDeltaBGThreshold < 0.2 ? .flagged(observed: observed) : .passed(observed: observed)
            },
            "G07": { s in
                guard let days = s.tddHistoryDays else {
                    return .flagged(observed: String(localized: "No TDD history"))
                }
                let observed = String(localized: "\(Int(days.rounded(.down))) days of history")
                return days < 7 ? .flagged(observed: observed) : .passed(observed: observed)
            },
            "G08": { s in
                .flagged(observed: s.dynamicISF.displayName)
            },
            "S04": { s in
                let observed = s.adjustmentFactorSigmoid.formatted(.percent)
                return s.adjustmentFactorSigmoid > 1 ? .flagged(observed: observed) : .passed(observed: observed)
            },
            "G06": { s in
                let observed = s.weightPercentage.formatted(.percent)
                return s.weightPercentage != 0.35 ? .flagged(observed: observed) : .passed(observed: observed)
            }
        ]

        static func run(snapshot: SettingsSnapshot, catalog: Catalog) -> SettingsCheckReport {
            let results = catalog.rules
                .filter { $0.kind == .settingsCheck && $0.status == .current }
                .sorted { $0.priority < $1.priority }
                .compactMap { rule -> CheckResult? in
                    guard let evaluate = evaluators[rule.id] else { return nil }
                    guard rule.applies(to: snapshot.dynamicISF) else {
                        return CheckResult(
                            rule: rule,
                            outcome: .notApplicable(
                                reason: String(localized: "Not used with Dynamic ISF \(snapshot.dynamicISF.displayName).")
                            )
                        )
                    }
                    return CheckResult(rule: rule, outcome: evaluate(snapshot))
                }
            return SettingsCheckReport(catalogVersion: catalog.version, snapshot: snapshot, results: results)
        }
    }
}

// MARK: - Guards applied to pattern findings

extension SettingsAnalysis {
    enum PatternGuards {
        /// Adjustment to pattern confidence plus the IDs of the guards that caused it.
        struct Effect: Equatable {
            var confidenceAdjustment: Int = 0
            var guardIDs: [String] = []
        }

        /// Phase 1 only enforces P9. P2, P5, P6 and P11 need historic data (Phase 2).
        static func effect(for snapshot: SettingsSnapshot) -> Effect {
            var effect = Effect()
            if snapshot.dia < 8 {
                effect.confidenceAdjustment -= 1
                effect.guardIDs.append("P9")
            }
            return effect
        }
    }
}
