import Observation
import SwiftUI

extension [Decimal] {
    /// The index of the ascending rate nearest to `rate`, when `rate` is less than half a step from it.
    func indexOfRate(_ rate: Decimal) -> Int? {
        guard let index = findClosestIndex(to: rate) else { return nil }
        let steps = [
            index > startIndex ? self[index] - self[index - 1] : nil,
            index < endIndex - 1 ? self[index + 1] - self[index] : nil
        ].compactMap { $0 }
        let halfStep = (steps.min() ?? 0.001) / 2
        return abs(self[index] - rate) < halfStep ? index : nil
    }
}

extension BasalProfileEditor {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() private var therapyProfileManager: TherapyProfileManager!
        @ObservationIgnored var profileName: String?
        @ObservationIgnored private var editedProfile: TrioTherapyProfile?
        /// The active profile when the editor opened; a save of the live settings is refused once it changed.
        @ObservationIgnored private var liveBase: TrioTherapyProfile?
        var bannerInfo: TherapyProfileBannerInfo?
        var profileSaveError: String?
        /// A rate of the schedule is not one the pump supports; its row shows the nearest supported rate.
        var hasUnsupportedRates = false

        var syncInProgress: Bool = false
        var initialItems: [Item] = []
        var items: [Item] = []
        var therapyItems: [TherapySettingItem] = []
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
            initialItems != items || hasUnsupportedRates
        }

        // Convert items to TherapySettingItem format
        func getTherapyItems() -> [TherapySettingItem] {
            items.map { item in
                TherapySettingItem(
                    time: timeValues[item.timeIndex],
                    value: rateValues[item.rateIndex]
                )
            }
        }

        // Update items from TherapySettingItem format
        func updateFromTherapyItems(_ therapyItems: [TherapySettingItem]) {
            items = therapyItems.map { therapyItem in
                let timeIndex = timeValues.firstIndex(where: { abs($0 - therapyItem.time) < 1 }) ?? 0
                let rateIndex = rateValues.indexOfRate(therapyItem.value) ?? rateValues
                    .findClosestIndex(to: therapyItem.value) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
        }

        override func subscribe() {
            rateValues = provider.supportedBasalRates ?? stride(from: 5.0, to: 1001.0, by: 5.0)
                .map { ($0.decimal ?? .zero) / 100 }
            editedProfile = profileName.flatMap { therapyProfileManager.profile(named: $0) }
            liveBase = profileName == nil ? therapyProfileManager.activeProfile() : nil
            bannerInfo = TherapyProfileBannerInfo.make(manager: therapyProfileManager, profileName: profileName)
            (items, hasUnsupportedRates) = Self.items(
                for: editedProfile?.basalProfileEntries ?? provider.profile,
                rateValues: rateValues,
                timeValues: timeValues
            )

            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            calcTotal()
        }

        /// The picker rows of a schedule. A rate the pump does not support takes the nearest supported rate, and
        /// `hasUnsupportedRates` is true.
        static func items(
            for entries: [BasalProfileEntry],
            rateValues: [Decimal],
            timeValues: [TimeInterval]
        ) -> (items: [Item], hasUnsupportedRates: Bool) {
            var hasUnsupportedRates = false
            let items = entries.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.minutes * 60)) ?? 0
                let rateIndex = rateValues.indexOfRate(value.rate) ?? rateValues.findClosestIndex(to: value.rate) ?? 0
                if !rateValues.indices.contains(rateIndex) || rateValues[rateIndex].rounded(scale: 3) != value.rate
                    .rounded(scale: 3)
                {
                    hasUnsupportedRates = true
                }
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
            return (items, hasUnsupportedRates)
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
            if let profileName, let editedProfile {
                saveToProfile(profileName, base: editedProfile, updated: editedProfile.replacing(basalProfile: profile))
                return
            }
            guard let liveBase, let provider else {
                syncInProgress = false
                return
            }
            Task { @MainActor in
                do {
                    self.liveBase = try await therapyProfileManager.saveLiveSettings(
                        expectedActiveName: liveBase.name,
                        expectedFingerprint: liveBase.fingerprint(units: .mgdL),
                        writesBasalSchedule: true
                    ) {
                        for try await _ in provider.saveProfile(profile).values {}
                    }
                    info(.settings, "Basal profile saved with \(profile.count) entries")
                    initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
                    hasUnsupportedRates = false
                } catch let profileError as TherapyProfileError {
                    profileSaveError = profileError.localizedDescription
                } catch let saveError {
                    error(.settings, "Saving basal profile failed", error: saveError)
                    showAlert = true
                }
                syncInProgress = false
            }
        }

        private func saveToProfile(_ name: String, base: TrioTherapyProfile, updated: TrioTherapyProfile) {
            Task { @MainActor in
                do {
                    editedProfile = try await therapyProfileManager.save(
                        updated,
                        originalName: name,
                        baseFingerprint: base.fingerprint(units: .mgdL)
                    )
                    initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
                    hasUnsupportedRates = false
                    info(.settings, "Basal schedule of profile \(updated.fingerprint(units: .mgdL)) saved")
                } catch {
                    profileSaveError = error.localizedDescription
                }
                syncInProgress = false
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
