import SwiftUI

extension CarbRatioEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var nightscout: NightscoutManager!
        @Published var items: [Item] = []
        @Published var initialItems: [Item] = []
        @Published var shouldDisplaySaving: Bool = false

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        let rateValues = stride(from: 10.0, to: 501.0, by: 1.0).map { ($0.decimal ?? .zero) / 10 }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            if initialItems.count != items.count {
                return true
            }

            for (initialItem, currentItem) in zip(initialItems, items) {
                if initialItem.rateIndex != currentItem.rateIndex || initialItem.timeIndex != currentItem.timeIndex {
                    return true
                }
            }

            return false
        }

        override func subscribe() {
            items = provider.profile.schedule.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.ratio) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
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
            shouldDisplaySaving = true

            let schedule = items.enumerated().map { _, item -> CarbRatioEntry in
                let fotmatter = DateFormatter()
                fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
                fotmatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return CarbRatioEntry(start: fotmatter.string(from: date), offset: minutes, ratio: rate)
            }
            let profile = CarbRatios(units: .grams, schedule: schedule)
            provider.saveProfile(profile)
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
            Task.detached(priority: .low) {
                do {
                    debug(.nightscout, "Attempting to upload CRs to Nightscout")
                    try await self.nightscout.uploadProfiles()
                } catch {
                    debug(.default, "Failed to upload CRs to Nightscout: \(error)")
                }
            }
        }

        func validate() {
            DispatchQueue.main.async {
                let uniq = Array(Set(self.items))
                let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                sorted.first?.timeIndex = 0
                if self.items != sorted {
                    self.items = sorted
                }
            }
        }
    }
}
