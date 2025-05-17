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
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var determinationStorage: DeterminationStorage!
        @ObservationIgnored @Injected() private var nightscout: NightscoutManager!

        var items: [Item] = []
        var initialItems: [Item] = []
        var shouldDisplaySaving: Bool = false

        let context = CoreDataStack.shared.newTaskContext()

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var rateValues: [Decimal] {
            let settingsProvider = PickerSettingsProvider.shared
            let sensitivityPickerSetting = PickerSetting(value: 100, step: 1, min: 9, max: 540, type: .glucose)
            return settingsProvider.generatePickerValues(from: sensitivityPickerSetting, units: units)
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            initialItems != items
        }

        private(set) var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units

            let profile = provider.profile

            items = profile.sensitivities.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                var rateIndex = rateValues.firstIndex(of: value.sensitivity)
                if rateIndex == nil {
                    // try to look up the closest value
                    if let min = rateValues.first, let max = rateValues.last {
                        if value.sensitivity >= (min - 1), value.sensitivity <= (max + 1) {
                            rateIndex = rateValues.findClosestIndex(to: value.sensitivity)
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
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return InsulinSensitivityEntry(sensitivity: rate, offset: minutes, start: fotmatter.string(from: date))
            }
            let profile = InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: sensitivities
            )
            provider.saveProfile(profile)
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

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
