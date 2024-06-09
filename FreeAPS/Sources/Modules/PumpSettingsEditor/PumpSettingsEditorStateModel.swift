import SwiftUI

extension PumpSettingsEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Published var maxBasal: Decimal = 0.0
        @Published var maxBolus: Decimal = 0.0
        @Published var dia: Decimal = 0.0

        @Published var syncInProgress = false

        override func subscribe() {
            let settings = provider.settings()
            maxBasal = settings.maxBasal
            maxBolus = settings.maxBolus
            dia = settings.insulinActionCurve
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

                } receiveValue: {}
                .store(in: &lifetime)
        }
    }
}
