import SwiftUI
import Swinject

extension Bolus {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!

        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var waitForSuggestion: Bool = false
        @Published var error: Bool = false
        @Published var errorString: Decimal = 0
        @Published var evBG: Int = 0
        @Published var insulin: Decimal = 0
        @Published var target: Decimal = 0
        @Published var isf: Decimal = 0
        @Published var percentage: Decimal = 0
        @Published var threshold: Decimal = 0
        @Published var minGuardBG: Decimal = 0
        @Published var minDelta: Decimal = 0
        @Published var expectedDelta: Decimal = 0
        @Published var minPredBG: Decimal = 0
        @Published var units: GlucoseUnits = .mmolL

        var waitForSuggestionInitial: Bool = false

        override func subscribe() {
            setupInsulinRequired()
            broadcaster.register(SuggestionObserver.self, observer: self)
            units = settingsManager.settings.units
            percentage = settingsManager.settings.insulinReqPercentage
            threshold = provider.suggestion?.threshold ?? 0

            if waitForSuggestionInitial {
                apsManager.determineBasal()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] ok in
                        guard let self = self else { return }
                        if !ok {
                            self.waitForSuggestion = false
                            self.insulinRequired = 0
                            self.insulinRecommended = 0
                        }
                    }.store(in: &lifetime)
            }
        }

        func add() {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            let maxAmount = Double(min(amount, provider.pumpSettings().maxBolus))

            unlockmanager.unlock()
                .sink { _ in } receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.apsManager.enactBolus(amount: maxAmount, isSMB: false)
                    self.showModal(for: nil)
                }
                .store(in: &lifetime)
        }

        func addWithoutBolus() {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            pumpHistoryStorage.storeEvents(
                [
                    PumpHistoryEvent(
                        id: UUID().uuidString,
                        type: .bolus,
                        timestamp: Date(),
                        amount: amount,
                        duration: nil,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil
                    )
                ]
            )
            showModal(for: nil)
        }

        func setupInsulinRequired() {
            DispatchQueue.main.async {
                self.insulinRequired = self.provider.suggestion?.insulinReq ?? 0

                // Manual Bolus recommendation (normally) yields a higher amount than the insulin reqiured amount computed for SMBs (auto boluses). A manual bolus threfore now (test) uses the Eventual BG for glucose prediction, whereas the insulinReg for SMBs uses the minPredBG for glucose prediction (typically lower than Eventual BG).

                var conversion: Decimal = 1.0
                if self.units == .mmolL {
                    conversion = 0.0555
                }

                self.evBG = self.provider.suggestion?.eventualBG ?? 0
                self.insulin = self.provider.suggestion?.insulinForManualBolus ?? 0
                self.target = self.provider.suggestion?.current_target ?? 0
                self.isf = self.provider.suggestion?.isf ?? 0

                if self.settingsManager.settings.insulinReqPercentage != 100 {
                    self.insulinRecommended = self.insulin * (self.settingsManager.settings.insulinReqPercentage / 100)
                } else { self.insulinRecommended = self.insulin }

                self.errorString = self.provider.suggestion?.manualBolusErrorString ?? 0
                if self.errorString != 0 {
                    self.error = true
                    self.minGuardBG = (self.provider.suggestion?.minGuardBG ?? 0) * conversion
                    self.minDelta = (self.provider.suggestion?.minDelta ?? 0) * conversion
                    self.expectedDelta = (self.provider.suggestion?.expectedDelta ?? 0) * conversion
                    self.minPredBG = (self.provider.suggestion?.minPredBG ?? 0) * conversion
                } else { self.error = false }

                self.insulinRecommended = self.apsManager
                    .roundBolus(amount: max(self.insulinRecommended, 0))
            }
        }
    }
}

extension Bolus.StateModel: SuggestionObserver {
    func suggestionDidUpdate(_: Suggestion) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
        setupInsulinRequired()
    }
}
