import CoreData
import Observation
import SwiftUI

extension [Decimal] {
    func findClosestIndex(to target: Element) -> Int? {
        guard !isEmpty else { return nil }

        return enumerated().min(by: {
            abs($0.element - target) < abs($1.element - target)
        })?.offset
    }
}

extension ISFEditor {
    @Observable final class StateModel: BaseStateModel<Provider>, TherapySettingsEditor.StateModel {
        @ObservationIgnored @Injected() var determinationStorage: DeterminationStorage!
        @ObservationIgnored @Injected() private var nightscout: NightscoutManager!
        @ObservationIgnored @Injected() private var tidepoolManager: TidepoolManager!
        @ObservationIgnored @Injected() private var broadcaster: Broadcaster!

        var items: [Item] = []
        var initialItems: [Item] = []
        var therapyItems: [TherapySettingsEditor.Item] = []
        var shouldDisplaySaving: Bool = false
        var isSaving: Bool { shouldDisplaySaving }

        let timeOptions = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var valueOptions: [Decimal] {
            let settingsProvider = PickerSettingsProvider.shared
            let sensitivityPickerSetting = PickerSetting(value: 100, step: 1, min: 9, max: 540, type: .glucose)
            return settingsProvider.generatePickerValues(from: sensitivityPickerSetting, units: units)
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeOptions.count - 1
        }

        var hasChanges: Bool {
            initialItems != items
        }

        private(set) var units: GlucoseUnits = .mgdL
        var unit: TherapySettingsEditor.Unit { units == .mgdL ? .mgdLPerUnit : .mmolLPerUnit }

        // Convert items to TherapySettingItem format
        func getTherapyItems() -> [TherapySettingsEditor.Item] {
            items.map { item in
                TherapySettingsEditor.Item(
                    time: timeOptions[item.timeIndex],
                    value: valueOptions[item.rateIndex]
                )
            }
        }

        // Update items from TherapySettingItem format
        func updateFromTherapyItems(_ therapyItems: [TherapySettingsEditor.Item]) {
            items = therapyItems.map { therapyItem in
                let timeIndex = timeOptions.firstIndex(where: { abs($0 - therapyItem.time) < 1 }) ?? 0
                let rateIndex = valueOptions.firstIndex(of: therapyItem.value) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
        }

        override func subscribe() {
            units = settingsManager.settings.units

            let profile = provider.profile

            items = profile.sensitivities.map { value in
                let timeIndex = timeOptions.firstIndex(of: Double(value.offset * 60)) ?? 0
                var rateIndex = valueOptions.firstIndex(of: value.sensitivity)
                if rateIndex == nil {
                    // try to look up the closest value
                    if let min = valueOptions.first, let max = valueOptions.last {
                        if value.sensitivity >= (min - 1), value.sensitivity <= (max + 1) {
                            rateIndex = valueOptions.findClosestIndex(to: value.sensitivity)
                        }
                    }
                }
                return Item(rateIndex: rateIndex ?? 0, timeIndex: timeIndex)
            }

            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
        }

        func add() {
            var time = 0
            var rate = 0
            if let last = items.last {
                time = last.timeIndex + 1
                rate = last.rateIndex
            }

            let newItem = Item(rateIndex: rate, timeIndex: time)

            items.append(newItem)
        }

        func save() {
            guard hasChanges else { return }
            shouldDisplaySaving.toggle()

            let sensitivities = items.map { item -> InsulinSensitivityEntry in
                let fotmatter = DateFormatter()
                fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
                fotmatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeOptions[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.valueOptions[item.rateIndex]
                return InsulinSensitivityEntry(sensitivity: rate, offset: minutes, start: fotmatter.string(from: date))
            }
            let profile = InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: sensitivities
            )
            provider.saveProfile(profile)
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            DispatchQueue.main.async {
                self.broadcaster.notify(InsulinSensitivitiesObserver.self, on: .main) {
                    $0.insulinSensitivitiesDidChange(profile)
                }
            }

            Task.detached(priority: .low) {
                do {
                    debug(.nightscout, "Attempting to upload ISF to Nightscout")
                    try await self.nightscout.uploadProfiles()
                } catch {
                    debug(
                        .default,
                        "\(DebuggingIdentifiers.failed) Faile to upload ISF to Nightscout: \(error)"
                    )
                }
            }

            Task.detached(priority: .low) {
                await self.tidepoolManager.uploadSettings()
            }

            // deactivate saving display after 1.25 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                self.shouldDisplaySaving = false
            }
        }

        func validate() {
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    let uniq = Array(Set(self.items))
                    let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                    sorted.first?.timeIndex = 0
                    if self.items != sorted {
                        self.items = sorted
                    }
                    if self.items.isEmpty {
                        self.units = self.settingsManager.settings.units
                    }
                }
            }
        }
    }
}

extension ISFEditor.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
