import Combine
import SwiftUI

extension PumpSettingsEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var nightscout: NightscoutManager!

        @Published var units: GlucoseUnits = .mgdL
        @Published var maxBasal: Decimal = 0.0 {
            didSet {
                checkForChanges()
            }
        }

        @Published var maxBolus: Decimal = 0.0 {
            didSet {
                checkForChanges()
            }
        }

        @Published var dia: Decimal = 0.0 {
            didSet {
                checkForChanges()
            }
        }

        @Published var syncInProgress = false
        @Published var hasChanged: Bool = false

        private var initialMaxBasal: Decimal = 0.0
        private var initialMaxBolus: Decimal = 0.0
        private var initialDia: Decimal = 0.0

        override func subscribe() {
            units = settingsManager.settings.units

            let settings = provider.settings()
            maxBasal = settings.maxBasal
            maxBolus = settings.maxBolus
            dia = settings.insulinActionCurve

            initialMaxBasal = settings.maxBasal
            initialMaxBolus = settings.maxBolus
            initialDia = settings.insulinActionCurve

            checkForChanges()
        }

        var unchanged: Bool {
            initialMaxBasal == maxBasal &&
                initialMaxBolus == maxBolus &&
                initialDia == dia
        }

        private func checkForChanges() {
            hasChanged = !unchanged
        }

        func save() {
            syncInProgress = true
            let settings = PumpSettings(
                insulinActionCurve: dia,
                maxBolus: maxBolus,
                maxBasal: maxBasal
            )
            provider.save(settings: settings)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    let settings = self.provider.settings()
                    self.syncInProgress = false
                    self.maxBasal = settings.maxBasal
                    self.maxBolus = settings.maxBolus
                    self.dia = settings.insulinActionCurve

                    self.initialMaxBasal = settings.maxBasal
                    self.initialMaxBolus = settings.maxBolus
                    self.initialDia = settings.insulinActionCurve

                    self.checkForChanges()

                    Task.detached(priority: .low) {
                        debug(.nightscout, "Attempting to upload DIA to Nightscout")
                        await self.nightscout.uploadProfiles()
                    }
                } receiveValue: {}
                .store(in: &lifetime)
        }
    }
}

extension PumpSettingsEditor.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
