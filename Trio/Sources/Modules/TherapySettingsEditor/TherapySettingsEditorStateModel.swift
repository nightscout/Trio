import CoreData
import Observation
import SwiftUI
import Swinject

extension TherapySettingsEditor {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() private var nightscout: NightscoutManager!
        @ObservationIgnored @Injected() private var tidepoolManager: TidepoolManager!

        private let therapyType: TherapyType

        let timeOptions = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }
        var valueOptions: [Decimal] = []
        var items: [Item] = []
        var initialItems: [Item] = []
        var isSaving: Bool = false
        var hasChanges: Bool { items != initialItems }
        var unit: Unit
        var total: Decimal = 0

        var showAlert: Bool {
            get { saveError != nil }
            set { saveError = !newValue ? nil : saveError }
        }

        var saveError: Error?

        init(_ therapyType: TherapyType) {
            self.therapyType = therapyType
            unit = therapyType.unit
        }

        override func subscribe() {
            unit = therapyType.getUnit(for: settingsManager.settings.units)
            valueOptions = getValueOptions(unit: unit)
            items = getItems()

            normalizeItemValues()
            updateInitialItems()
        }

        private func getValueOptions(unit: Unit) -> [Decimal] {
            switch therapyType {
            case .basalRate: getBasalValueOptions(unit: unit)
            case .carbRatio: getCarbRatioValueOptions(unit: unit)
            case .insulinSensitivity: getInsulinSensitivityValueOptions(unit: unit)
            case .bloodGlucoseTarget: getBloodGlucoseTargetOptions(unit: unit)
            }
        }

        private func getItems() -> [Item] {
            switch therapyType {
            case .basalRate: getBasalItems()
            case .carbRatio: getCarbRatioItems()
            case .insulinSensitivity: getInsulinSensitivityItems()
            case .bloodGlucoseTarget: getBloodGlucoseTargetItems()
            }
        }

        private func normalizeItemValues() {
            for index in items.indices where !valueOptions.contains(items[index].value) {
                if let closestValue = valueOptions.findClosestValue(to: items[index].value) {
                    items[index].value = closestValue
                }
            }
        }

        private func updateInitialItems() {
            initialItems = items.map { Item(copying: $0) }
        }

        func save() {
            guard hasChanges else { return }

            isSaving = true

            Task { @MainActor in
                defer {
                    isSaving = false
                }

                async let saveOperation = saveItems()
                async let minimumDisplayTime = Task.sleep(for: .seconds(1.25))

                do {
                    try? await minimumDisplayTime
                    try await saveOperation

                    uploadToNightscout()
                    uploadToTidepool()
                    updateInitialItems()
                } catch let saveError {
                    self.saveError = saveError
                    error(.settings, "Saving \(self.therapyType.title) profile failed", error: saveError)
                }
            }
        }

        @MainActor private func saveItems() async throws {
            switch therapyType {
            case .basalRate: try await saveBasalItems(items)
            case .carbRatio: saveCarbRatioItems(items)
            case .insulinSensitivity: saveInsulinSensitivityItems(items)
            case .bloodGlucoseTarget: saveBloodGlucoseTargetItems(items)
            }
        }

        private func uploadToNightscout() {
            Task.detached(priority: .low) {
                do {
                    try await self.nightscout.uploadProfiles()
                } catch {
                    warning(.nightscout, "Uploading profile after \(self.therapyType.title) change failed", error: error)
                }
            }
        }

        private func uploadToTidepool() {
            Task.detached(priority: .low) {
                await self.tidepoolManager.uploadSettings()
            }
        }

        func validate() {
            if therapyType.totalUnit != nil {
                updateTotal()
            }
        }

        private func updateTotal() {
            total = calcTotal()
        }

        private func calcTotal() -> Decimal {
            let sorted = items.sorted { $0.time < $1.time }
            guard !sorted.isEmpty else { return 0 }

            return sorted.enumerated().reduce(Decimal(0)) { total, element in
                let (index, item) = element
                let end = index + 1 < sorted.count ? sorted[index + 1].time / 60 : 24 * 60
                let minutes = end - item.time / 60
                guard minutes > 0 else { return total }
                return total + item.value * Decimal(minutes) / 60
            }
        }
    }
}

extension Array where Element == Decimal {
    func findClosestValue(to target: Element) -> Element? {
        guard !isEmpty else { return nil }

        return enumerated().min(by: {
            abs($0.element - target) < abs($1.element - target)
        })?.element
    }
}
