import Combine
import LoopKitUI
import RileyLinkBLEKit

extension PumpConfig {
    final class Provider: BaseProvider, PumpConfigProvider {
        @Injected() var apsManager: APSManager!

        func setPumpManager(_ manager: PumpManagerUI) {
            apsManager.pumpManager = manager
        }

        var pumpDisplayState: AnyPublisher<PumpDisplayState?, Never> {
            apsManager.pumpDisplayState.eraseToAnyPublisher()
        }

        func basalProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        var alertNotAck: AnyPublisher<Bool, Never> {
            deviceManager.alertHistoryStorage.alertNotAck.eraseToAnyPublisher()
        }

        func initialAlertNotAck() -> Bool {
            deviceManager.alertHistoryStorage.recentNotAck().isNotEmpty
        }
    }
}
