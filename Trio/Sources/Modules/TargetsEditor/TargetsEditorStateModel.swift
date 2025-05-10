import SwiftUI

extension TargetsEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var nightscout: NightscoutManager!
        @Injected() private var broadcaster: Broadcaster!

        @Published var items: [Item] = []
        @Published var initialItems: [Item] = []
        @Published var shouldDisplaySaving: Bool = false

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var rateValues: [Decimal] {
            let settingsProvider = PickerSettingsProvider.shared
            let glucoseSetting = PickerSetting(value: 110, step: 1, min: 72, max: 180, type: .glucose)
            return settingsProvider.generatePickerValues(from: glucoseSetting, units: units)
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

            items = profile.targets.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let lowIndex = rateValues.firstIndex(of: value.low) ?? 0
                let highIndex = rateValues.firstIndex(of: value.high) ?? 0
                return Item(lowIndex: lowIndex, highIndex: highIndex, timeIndex: timeIndex)
            }

            initialItems = items.map { Item(lowIndex: $0.lowIndex, highIndex: $0.highIndex, timeIndex: $0.timeIndex) }
        }

        func add() {
            var time = 0
            var low = 0
            var high = 0
            if let last = items.last {
                time = last.timeIndex + 1
                low = last.lowIndex
                high = low
            }

            let newItem = Item(lowIndex: low, highIndex: high, timeIndex: time)

            items.append(newItem)
        }

        func save() {
            guard hasChanges else { return }
            shouldDisplaySaving.toggle()

            let targets = items.map { item -> BGTargetEntry in
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let low = self.rateValues[item.lowIndex]
                let high = low
                return BGTargetEntry(low: low, high: high, start: formatter.string(from: date), offset: minutes)
            }
            let profile = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: targets)
            provider.saveProfile(profile)
            initialItems = items.map { Item(lowIndex: $0.lowIndex, highIndex: $0.highIndex, timeIndex: $0.timeIndex) }

            DispatchQueue.main.async {
                self.broadcaster.notify(BGTargetsObserver.self, on: .main) {
                    $0.bgTargetsDidChange(profile)
                }
            }

            Task.detached(priority: .low) {
                do {
                    debug(.nightscout, "Attempting to upload targets to Nightscout")
                    try await self.nightscout.uploadProfiles()
                } catch {
                    debug(
                        .default,
                        "\(DebuggingIdentifiers.failed) failed to upload targets to Nightscout: \(error)"
                    )
                }
            }
        }

        func validate() {
            DispatchQueue.main.async {
                let uniq = Array(Set(self.items))
                let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                    .map { item -> Item in
                        Item(lowIndex: item.lowIndex, highIndex: item.highIndex, timeIndex: item.timeIndex)
                    }
                sorted.first?.timeIndex = 0
                self.items = sorted

                if self.items.isEmpty {
                    self.units = self.settingsManager.settings.units
                }
            }
        }
    }
}
