import Combine
import CoreData
import Observation
import SwiftUI

extension DynamicSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!
        @Injected() var tddStorage: TDDStorage!

        // this is an *interim* fix to provide better UI/UX
        // FIXME: needs to be refactored, once oref-swift lands and dynamicISF becomes swift-bound
        @Published var dynamicSensitivityType: DynamicSensitivityType = .disabled {
            didSet {
                switch dynamicSensitivityType {
                case .logarithmic:
                    useNewFormula = true
                    sigmoid = false
                case .sigmoid:
                    useNewFormula = true
                    sigmoid = true
                default:
                    useNewFormula = false
                    sigmoid = false
                }
            }
        }

        @Published var hasValidTDD: Bool = false
        @Published var useNewFormula: Bool = false
        @Published var sigmoid: Bool = false
        @Published var adjustmentFactor: Decimal = 0.8
        @Published var adjustmentFactorSigmoid: Decimal = 0.5
        @Published var weightPercentage: Decimal = 0.65
        @Published var tddAdjBasal: Bool = false

        @ObservedObject var pickerSettingsProvider = PickerSettingsProvider.shared

        var units: GlucoseUnits = .mgdL

        let context = CoreDataStack.shared.newTaskContext()

        override func subscribe() {
            units = settingsManager.settings.units

            /// DynamicISF handling
            /// Initially, load once from storage and infer `dynamicSensitivityType` based on values of `useNewFormula` (log) and/or `sigmoid`
            let storedUseNewFormula = settingsManager.preferences.useNewFormula
            let storedSigmoid = settingsManager.preferences.sigmoid
            inferDynamicSensitivityType(useNewFormula: storedUseNewFormula, sigmoid: storedSigmoid)
            /// Subsequently, subscribe to changes from the UI and persist them in the (kept for now) two variables
            subscribePreferencesSetting(\.useNewFormula, on: $useNewFormula) { _ in }
            subscribePreferencesSetting(\.sigmoid, on: $sigmoid) { _ in }

            subscribePreferencesSetting(\.adjustmentFactor, on: $adjustmentFactor) { adjustmentFactor = $0 }
            subscribePreferencesSetting(\.adjustmentFactorSigmoid, on: $adjustmentFactorSigmoid) { adjustmentFactorSigmoid = $0 }
            subscribePreferencesSetting(\.weightPercentage, on: $weightPercentage) { weightPercentage = $0 }
            subscribePreferencesSetting(\.tddAdjBasal, on: $tddAdjBasal) { tddAdjBasal = $0 }

            Task {
                do {
                    let hasValidTDD = try await tddStorage.hasSufficientTDD()
                    await MainActor.run {
                        self.hasValidTDD = hasValidTDD
                    }
                } catch {
                    debug(.coreData, "Error when fetching TDD for validity checking: \(error)")
                    await MainActor.run {
                        hasValidTDD = false
                    }
                }
            }
        }

        /// Infers the `dynamicSensitivityType` based on the stored values of `useNewFormula` and `sigmoid`.
        /// - Logic:
        ///   - If `useNewFormula` is `true` and `sigmoid` is `false`, sets type to `.logarithmic`.
        ///   - If both `useNewFormula` and `sigmoid` are `true`, sets type to `.sigmoid`.
        ///   - Otherwise, sets type to `.disabled`.
        ///
        /// This is used at startup to derive the dynamic sensitivity state from persisted values until
        /// a future refactor makes `dynamicSensitivityType` a first-class stored preference.
        // FIXME: needs to be refactored, once oref-swift lands and dynamicISF becomes swift-bound
        private func inferDynamicSensitivityType(useNewFormula: Bool, sigmoid: Bool) {
            if useNewFormula {
                dynamicSensitivityType = sigmoid ? .sigmoid : .logarithmic
            } else {
                dynamicSensitivityType = .disabled
            }
        }

        /// Checks if there is enough Total Daily Dose (TDD) data collected over the past 7 days.
        ///
        /// This function performs a count fetch for TDDStored records in Core Data where:
        /// - The record's date is within the last 7 days.
        /// - The total value is greater than 0.
        ///
        /// It then checks if at least 85% of the expected data points are present,
        /// assuming at least 288 expected entries per day (one every 5 minutes).
        ///
        /// - Returns: `true` if sufficient TDD data is available, otherwise `false`.
        /// - Throws: An error if the Core Data count operation fails.
        private func hasSufficientTDD() throws -> Bool {
            var result = false

            context.performAndWait {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "TDDStored")
                fetchRequest.predicate = NSPredicate(
                    format: "date > %@ AND total > 0",
                    Date().addingTimeInterval(-86400 * 7) as NSDate
                )
                fetchRequest.resultType = .countResultType

                let count = (try? context.count(for: fetchRequest)) ?? 0
                let threshold = Int(Double(7 * 288) * 0.85)
                result = count >= threshold
            }

            return result
        }
    }
}

extension DynamicSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}

extension DynamicSettings {
    enum DynamicSensitivityType: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
        var id: String { rawValue }
        case disabled
        case logarithmic
        case sigmoid

        var displayName: String {
            switch self {
            case .disabled:
                return String(localized: "Disabled")

            case .logarithmic:
                return String(localized: "Logarithmic")

            case .sigmoid:
                return String(localized: "Sigmoid")
            }
        }
    }
}
