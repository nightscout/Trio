import Foundation
import LoopKitUI
import SwiftDate

extension Home {
    final class Provider: BaseProvider, HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() var carbsStorage: CarbsStorage!

        var suggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }

        var enactedSuggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)
        }

        var profile: BGTargets {
            storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mmolL, userPrefferedUnits: .mmolL, targets: [])
        }

        func heartbeatNow() {
            apsManager.heartbeat(date: Date())
        }

        func filteredGlucose(hours: Int) -> [BloodGlucose] {
            glucoseStorage.recent().filter {
                $0.dateString.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func pumpHistory(hours: Int) -> [PumpHistoryEvent] {
            pumpHistoryStorage.recent().filter {
                $0.timestamp.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func tempTargets(hours: Int) -> [TempTarget] {
            tempTargetsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func tempTarget() -> TempTarget? {
            tempTargetsStorage.current()
        }

        func carbs(hours: Int) -> [CarbsEntry] {
            carbsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        func pumpBattery() -> Battery? {
            storage.retrieve(OpenAPS.Monitor.battery, as: Battery.self)
        }

        func pumpReservoir() -> Decimal? {
            storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self)
        }

        func autotunedBasalProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.profile, as: Autotune.self)?.basalProfile
                ?? storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }

        func basalProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }
    }
}
