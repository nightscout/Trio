import Foundation

// MARK: - Catalog (data)

extension SettingsAnalysis {
    /// Rule texts from `json/settings-analysis/pattern-catalog.json`. The logic
    /// for each rule lives in `SettingsChecks.evaluators`.
    struct Catalog: Decodable {
        let version: String
        let source: String
        let rules: [Rule]
        let guards: [Guard]

        static let bundledResource = "json/settings-analysis/pattern-catalog"

        static func loadBundled(bundle: Bundle = .main) throws -> Catalog {
            guard let url = bundle.url(forResource: bundledResource, withExtension: "json") else {
                throw CatalogError.missing
            }
            return try decode(Data(contentsOf: url))
        }

        static func decode(_ data: Data) throws -> Catalog {
            try JSONDecoder().decode(Catalog.self, from: data)
        }

        func `guard`(_ id: String) -> Guard? {
            guards.first { $0.id == id }
        }
    }

    enum CatalogError: LocalizedError {
        case missing

        var errorDescription: String? {
            String(localized: "The settings analysis rule catalog is missing from the app bundle.")
        }
    }

    struct Rule: Decodable, Identifiable, Hashable {
        enum Kind: String, Decodable {
            /// Fires on the current configuration alone.
            case settingsCheck
            /// Fires on patterns in historic data (Phase 2+).
            case pattern
        }

        enum Status: String, Decodable {
            case current
            case superseded
            case rejected
            case retired
        }

        enum Direction: String, Decodable {
            case increase
            case decrease
            case review
            case restoreDefault
            case considerChange
            case wait
            case noChange

            var displayName: String {
                switch self {
                case .increase: return String(localized: "Usually points to an increase")
                case .decrease: return String(localized: "Usually points to a decrease")
                case .review: return String(localized: "Worth reviewing")
                case .restoreDefault: return String(localized: "Default usually recommended")
                case .considerChange: return String(localized: "Worth considering a change")
                case .wait: return String(localized: "Usually better to wait")
                case .noChange: return String(localized: "No settings change")
                }
            }
        }

        enum Readiness: String, Decodable, Comparable {
            case low
            case medium
            case high

            private var order: Int {
                switch self {
                case .low: return 0
                case .medium: return 1
                case .high: return 2
                }
            }

            static func < (lhs: Readiness, rhs: Readiness) -> Bool { lhs.order < rhs.order }

            var confidence: Confidence {
                switch self {
                case .low: return .low
                case .medium: return .medium
                case .high: return .high
                }
            }
        }

        let id: String
        let kind: Kind
        let status: Status
        /// Lower runs first and wins "Start here" (guard P1: order of operations).
        let priority: Int
        let title: String
        let setting: String
        let direction: Direction
        let readiness: Readiness
        let evidenceCount: Int
        let lastSeen: String?
        /// Dynamic ISF modes the rule applies to: "all", "off", "logarithmic", "sigmoid".
        let modes: [String]
        let finding: String
        let advice: String
        let rationale: String
        let guards: [String]

        func applies(to mode: DynamicISFMode) -> Bool {
            modes.contains("all") || modes.contains(mode.rawValue)
        }
    }

    struct Guard: Decodable, Identifiable, Hashable {
        let id: String
        /// Rollout phase in which the guard is enforced by the engine (0 = curation rule).
        let phase: Int
        let text: String
    }
}
