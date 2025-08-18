import Observation
import SwiftUI

extension BasalProfileEditor {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() private var nightscout: NightscoutManager!
        @ObservationIgnored @Injected() private var broadcaster: Broadcaster!

        var syncInProgress: Bool = false
        var initialItems: [Item] = []
        var items: [Item] = []
        var total: Decimal = 0.0
        var showAlert: Bool = false
        var chartData: [BasalProfile]? = []

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        private(set) var rateValues: [Decimal] = []

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            initialItems != items
        }

        override func subscribe() {
            rateValues = provider.supportedBasalRates ?? stride(from: 5.0, to: 1001.0, by: 5.0)
                .map { ($0.decimal ?? .zero) / 100 }
            items = provider.profile.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.minutes * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.rate) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }

            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            calcTotal()
        }

        func calcTotal() {
            let profile = items.map { item -> BasalProfileEntry in
                let fotmatter = DateFormatter()
                fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
                fotmatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return BasalProfileEntry(start: fotmatter.string(from: date), minutes: minutes, rate: rate)
            }

            var profileWith24hours = profile.map(\.minutes)
            profileWith24hours.append(24 * 60)
            let pr2 = zip(profile, profileWith24hours.dropFirst())
            total = pr2.reduce(0) { $0 + (Decimal($1.1 - $1.0.minutes) / 60) * $1.0.rate }
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
            calcTotal()
        }

        func save() {
            guard hasChanges else { return }

            syncInProgress = true
            let profile = items.map { item -> BasalProfileEntry in
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return BasalProfileEntry(start: formatter.string(from: date), minutes: minutes, rate: rate)
            }
            provider.saveProfile(profile)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    self.syncInProgress = false
                    switch completion {
                    case .finished:
                        // Successfully saved and synced
                        self.initialItems = self.items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

                        Task.detached(priority: .low) {
                            do {
                                debug(.nightscout, "Attempting to upload basal rates to Nightscout")
                                try await self.nightscout.uploadProfiles()
                            } catch {
                                debug(.default, "Failed to upload basal rates to Nightscout: \(error)")
                            }
                        }
                    case .failure:
                        // Handle the error, show error message
                        self.showAlert = true
                    }
                } receiveValue: {
                    // Handle any successful value if needed
                    print("We were successful")
                }
                .store(in: &lifetime)

            DispatchQueue.main.async {
                self.broadcaster.notify(BasalProfileObserver.self, on: .main) {
                    $0.basalProfileDidChange(profile)
                }
            }
        }

        @MainActor func validate() {
            let uniq = Array(Set(items))
            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
            sorted.first?.timeIndex = 0
            if items != sorted {
                items = sorted
            }
            calcTotal()
        }

        func availableTimeIndices(_ itemIndex: Int) -> [Int] {
            // avoid index out of range issues
            guard itemIndex >= 0, itemIndex < items.count else {
                return []
            }

            let usedIndicesByOtherItems = items
                .enumerated()
                .filter { $0.offset != itemIndex }
                .map(\.element.timeIndex)

            return (0 ..< timeValues.count).filter { !usedIndicesByOtherItems.contains($0) }
        }

        @MainActor func calculateChartData() {
            var basals: [BasalProfile] = []
            let tzOffset = TimeZone.current.secondsFromGMT() * -1

            basals.append(contentsOf: items.enumerated().map { index, item in
                let startDate = Date(timeIntervalSinceReferenceDate: self.timeValues[item.timeIndex])
                var endDate = Date(timeIntervalSinceReferenceDate: self.timeValues.last!).addingTimeInterval(30 * 60)
                if self.items.count > index + 1 {
                    let nextItem = self.items[index + 1]
                    endDate = Date(timeIntervalSinceReferenceDate: self.timeValues[nextItem.timeIndex])
                }

                return BasalProfile(
                    amount: Double(self.rateValues[item.rateIndex]),
                    isOverwritten: false,
                    startDate: startDate.addingTimeInterval(TimeInterval(tzOffset)),
                    endDate: endDate.addingTimeInterval(TimeInterval(tzOffset))
                )
            })
            basals.sort(by: {
                $0.startDate > $1.startDate
            })

            chartData = basals
        }
    }
}
