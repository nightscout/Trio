import Combine
import Foundation
import LoopKit

extension BasalProfileEditor {
    final class Provider: BaseProvider, BasalProfileEditorProvider {
        private let processQueue = DispatchQueue(label: "BasalProfileEditorProvider.processQueue")

        var profile: [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }

        var supportedBasalRates: [Decimal]? {
            deviceManager.pumpManager.map { Self.editorRates($0.supportedBasalRates) }
        }

        static func editorRates(_ supportedBasalRates: [Double]) -> [Decimal] {
            // Drops 0 even where the pump accepts it: oref rejects a schedule containing a 0 rate, so a scheduled
            // basal of 0 would be saved and then refused. Zero temp basals are unaffected — they do not come
            // from this list. Rates are kept at three decimal places, so a rate such as 0.07 is exactly 0.07.
            supportedBasalRates.filter { $0 > 0 }.map { Decimal($0).rounded(scale: 3) }
        }

        func saveProfile(_ profile: [BasalProfileEntry]) -> AnyPublisher<Void, Error> {
            guard let pump = deviceManager?.pumpManager else {
                warning(.settings, "Basal profile not saved, no pump connected")
                return Fail(error: NSError()).eraseToAnyPublisher()
            }

            let syncValues = profile.map {
                RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: pump.scheduleValue(for: $0.rate))
            }

            return Future { promise in
                pump.syncBasalRateSchedule(items: syncValues) { result in
                    switch result {
                    case .success:
                        self.storage.save(profile, as: OpenAPS.Settings.basalProfile)
                        promise(.success(()))
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
            }.eraseToAnyPublisher()
        }
    }
}

extension PumpManager {
    /// The pump's own value for a scheduled basal rate: its supported rate within 0.0005 U/h of `rate`, otherwise
    /// `rate` as a `Double`. A `Decimal` converts to a `Double` that can sit just below the pump's value, which a pump
    /// that truncates would run as the next lower rate.
    func scheduleValue(for rate: Decimal) -> Double {
        Self.scheduleValue(for: rate, supportedRates: supportedBasalRates)
    }

    static func scheduleValue(for rate: Decimal, supportedRates: [Double]) -> Double {
        let value = Double(rate)
        guard let nearest = supportedRates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(nearest - value) < 0.0005
        else { return value }
        return nearest
    }
}
