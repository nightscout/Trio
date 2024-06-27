import SwiftUI

extension TargetsEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Published var items: [Item] = []

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var rateValues: [Decimal] {
            switch units {
            case .mgdL:
                return stride(from: 72, to: 180.01, by: 1.0).map { $0 }
            case .mmolL:
                return stride(from: 4.0, to: 10.01, by: 0.1).map { $0 }
            }
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            let profile = provider.profile
            units = profile.units
            items = profile.targets.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let lowIndex = rateValues.firstIndex(of: value.low) ?? 0
                let highIndex = rateValues.firstIndex(of: value.high) ?? 0
                return Item(lowIndex: lowIndex, highIndex: highIndex, timeIndex: timeIndex)
            }
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
            let profile = BGTargets(units: units, userPrefferedUnits: settingsManager.settings.units, targets: targets)
            provider.saveProfile(profile)
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
