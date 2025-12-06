import Combine
import SwiftUI

extension CalendarEventSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!
        @Injected() var calendarManager: CalendarManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var useCalendar = false
        @Published var displayCalendarIOBandCOB = false
        @Published var displayCalendarEmojis = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil

        override func subscribe() {
            units = settingsManager.settings.units

            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = calendarManager.calendarIDs()

            subscribeSetting(\.useCalendar, on: $useCalendar) { useCalendar = $0 }
            subscribeSetting(\.displayCalendarIOBandCOB, on: $displayCalendarIOBandCOB) { displayCalendarIOBandCOB = $0 }
            subscribeSetting(\.displayCalendarEmojis, on: $displayCalendarEmojis) { displayCalendarEmojis = $0 }

            observeCreateCalendarEvents()
            observeCurrentCalendarID()
        }

        private func observeCreateCalendarEvents() {
            Task {
                for await ok in $useCalendar.removeDuplicates().values {
                    guard ok else { continue }
                    let accessGranted = await calendarManager.requestAccessIfNeeded()
                    if accessGranted {
                        let ids = calendarManager.calendarIDs()
                        await MainActor.run {
                            self.calendarIDs = ids
                        }
                    }
                }
            }
        }

        private func observeCurrentCalendarID() {
            Task {
                for await id in $currentCalendarID.removeDuplicates().values {
                    if id.isEmpty {
                        calendarManager.currentCalendarID = nil
                    } else {
                        calendarManager.currentCalendarID = id
                    }
                }
            }
        }
    }
}

extension CalendarEventSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
