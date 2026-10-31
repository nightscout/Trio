import Combine
import Foundation
import LoopKit

extension TherapySettingsEditor.Provider {
    var supportedBasalRates: [Decimal]? {
        // Drops 0 even where the pump accepts it: oref rejects a schedule containing a 0 rate, so a scheduled
        // basal of 0 would be saved and then refused. Zero temp basals are unaffected — they do not come
        // from this list.
        deviceManager.pumpManager?.supportedBasalRates
            .filter { $0 > 0 }
            .map { Decimal($0) }
    }

    var basalProfile: [BasalProfileEntry] {
        storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
            ?? []
    }

    func saveBasalProfile(_ profile: [BasalProfileEntry]) async throws {
        guard let pump = deviceManager?.pumpManager else {
            debugPrint("\(DebuggingIdentifiers.failed) No pump found; cannot save basal profile!")
            throw TherapySettingsEditor.BasalSaveError.noPumpAvailable
        }

        let syncValues = profile.map {
            RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
        }

        try await withCheckedThrowingContinuation { continuation in
            pump.syncBasalRateSchedule(items: syncValues) { result in
                switch result {
                case .success:
                    self.storage.save(profile, as: OpenAPS.Settings.basalProfile)
                    continuation.resume(returning: ())
                case .failure:
                    continuation.resume(throwing: TherapySettingsEditor.BasalSaveError.synchronizationFailed)
                }
            }
        }
    }
}

extension TherapySettingsEditor {
    enum BasalSaveError: LocalizedError {
        case noPumpAvailable
        case synchronizationFailed

        var errorDescription: String? {
            switch self {
            case .noPumpAvailable:
                return String(
                    localized: "No pump is available. Your basal profile was not saved."
                )

            case .synchronizationFailed:
                return String(
                    localized: "Trio could not communicate with your pump. Changes to your basal profile were not saved."
                )
            }
        }
    }
}
