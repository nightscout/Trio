import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI

extension AlgorithmAdvancedSettings {
    final class Provider: BaseProvider, AlgorithmAdvancedSettingsProvider {
        private let processQueue = DispatchQueue(label: "AlgorithmAdvancedSettingsProvider.processQueue")
        @Injected() private var broadcaster: Broadcaster!

        func settings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 10.0, maxBolus: 10, maxBasal: 2)
        }

        func savePreferences(_ preferences: Preferences) {
            storage.save(preferences, as: OpenAPS.Settings.preferences)
            processQueue.async {
                self.broadcaster.notify(PreferencesObserver.self, on: self.processQueue) {
                    $0.preferencesDidChange(preferences)
                }
            }
        }

        func save(settings: PumpSettings) -> AnyPublisher<Void, Error> {
            func save(_ settings: PumpSettings) {
                storage.save(settings, as: OpenAPS.Settings.settings)
                processQueue.async {
                    self.broadcaster.notify(PumpSettingsObserver.self, on: self.processQueue) {
                        $0.pumpSettingsDidChange(settings)
                    }
                }
            }

            guard let pump = deviceManager?.pumpManager else {
                save(settings)
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
            let limits = DeliveryLimits(
                maximumBasalRate: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: Double(settings.maxBasal)),
                maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: Double(settings.maxBolus))
            )
            return Future { promise in
                self.processQueue.async {
                    pump.syncDeliveryLimits(limits: limits) { result in
                        switch result {
                        case let .success(actual):
                            // Store the limits from the pumpManager to ensure the correct values
                            // Example: Dana pumps don't allow to set these limits, only to fetch them
                            // This will ensure we always have the correct values stored
                            save(PumpSettings(
                                insulinActionCurve: settings.insulinActionCurve,
                                maxBolus: Decimal(
                                    actual.maximumBolus?
                                        .doubleValue(for: .internationalUnit()) ?? Double(settings.maxBolus)
                                ),
                                maxBasal: Decimal(
                                    actual.maximumBasalRate?
                                        .doubleValue(for: .internationalUnitsPerHour) ?? Double(settings.maxBasal)
                                )
                            ))
                            promise(.success(()))
                        case let .failure(error):
                            promise(.failure(error))
                        }
                    }
                }
            }.eraseToAnyPublisher()
        }
    }
}
