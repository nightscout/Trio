import SwiftUI

extension PumpSettingsEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Published var maxBasal: Decimal = 0.0
        @Published var maxBolus: Decimal = 0.0
        @Published var dia: Decimal = 0.0
        @Published var maxCarbs: Decimal = 250

        @Published var syncInProgress = false

        override func subscribe() {
            let settings = provider.settings()
            maxBasal = settings.maxBasal
            maxBolus = settings.maxBolus
            dia = settings.insulinActionCurve
            subscribeSetting(\.maxCarbs, on: $maxCarbs) { maxCarbs = $0 }
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
                    self.syncInProgress = false

                } receiveValue: {}
                .store(in: &lifetime)
        }
    }
}
