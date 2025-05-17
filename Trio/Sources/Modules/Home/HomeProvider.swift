import Foundation
import LoopKitUI
import SwiftDate

extension Home {
    final class Provider: BaseProvider, HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!

        func pumpTimeZone() -> TimeZone? {
            apsManager.pumpManager?.status.timeZone
        }

        func heartbeatNow() {
            apsManager.heartbeat(date: Date())
        }

        func pumpSettings() async -> PumpSettings {
            await storage.retrieveAsync(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
        }

        func pumpReservoir() async -> Decimal? {
            await storage.retrieveAsync(OpenAPS.Monitor.reservoir, as: Decimal.self)
        }

        func getBasalProfile() async -> [BasalProfileEntry] {
            await storage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }

        func getBGTargets() async -> BGTargets {
            await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        }
    }
}
