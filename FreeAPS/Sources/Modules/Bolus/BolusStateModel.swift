import LoopKit
import SwiftUI
import Swinject

extension Bolus {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        // added for bolus calculator
        @Injected() var settings: SettingsManager!
        @Injected() var nsManager: NightscoutManager!

        @Published var suggestion: Suggestion?
        @Published var predictions: Predictions?
        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var units: GlucoseUnits = .mmolL
        @Published var percentage: Decimal = 0
        @Published var threshold: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var errorString: Decimal = 0
        @Published var evBG: Int = 0
        @Published var insulin: Decimal = 0
        @Published var isf: Decimal = 0
        @Published var error: Bool = false
        @Published var minGuardBG: Decimal = 0
        @Published var minDelta: Decimal = 0
        @Published var expectedDelta: Decimal = 0
        @Published var minPredBG: Decimal = 0
        @Published var waitForSuggestion: Bool = false
        @Published var carbRatio: Decimal = 0

        var waitForSuggestionInitial: Bool = false

        // added for bolus calculator
        @Published var recentGlucose: BloodGlucose?
        @Published var target: Decimal = 0
        @Published var cob: Decimal = 0
        @Published var iob: Decimal = 0

        @Published var currentBG: Decimal = 0
        @Published var fifteenMinInsulin: Decimal = 0
        @Published var deltaBG: Decimal = 0
        @Published var targetDifferenceInsulin: Decimal = 0
        @Published var wholeCobInsulin: Decimal = 0
        @Published var iobInsulinReduction: Decimal = 0
        @Published var wholeCalc: Decimal = 0
        @Published var roundedWholeCalc: Decimal = 0
        @Published var insulinCalculated: Decimal = 0
        @Published var roundedInsulinCalculated: Decimal = 0
        @Published var fraction: Decimal = 0
        @Published var useCalc: Bool = false
        @Published var basal: Decimal = 0
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var useFattyMealCorrectionFactor: Bool = false
        @Published var displayPredictions: Bool = true

        @Published var currentBasal: Decimal = 0
        @Published var sweetMeals: Bool = false
        @Published var sweetMealFactor: Decimal = 0
        @Published var useSuperBolus: Bool = false
        @Published var superBolusInsulin: Decimal = 0

        @Published var meal: [CarbsEntry]?
        @Published var carbs: Decimal = 0
        @Published var fat: Decimal = 0
        @Published var protein: Decimal = 0
        @Published var note: String = ""

        override func subscribe() {
            setupInsulinRequired()
            broadcaster.register(SuggestionObserver.self, observer: self)
            units = settingsManager.settings.units
            percentage = settingsManager.settings.insulinReqPercentage
            threshold = provider.suggestion?.threshold ?? 0
            maxBolus = provider.pumpSettings().maxBolus
            // added
            fraction = settings.settings.overrideFactor
            useCalc = settings.settings.useCalc
            fattyMeals = settings.settings.fattyMeals
            fattyMealFactor = settings.settings.fattyMealFactor
            sweetMeals = settings.settings.sweetMeals
            sweetMealFactor = settings.settings.sweetMealFactor
            displayPredictions = settings.settings.displayPredictions

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
            if let notNilSugguestion = provider.suggestion {
                suggestion = notNilSugguestion
                if let notNilPredictions = suggestion?.predictions {
                    predictions = notNilPredictions
                }
            }
        }

        func getCurrentBasal() {
            let basalEntries = provider.getProfile()

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            let currentTime = dateFormatter.string(from: Date())

            // loop throug entries and get current basal entry
            for (index, entry) in basalEntries.enumerated() {
                if let entryStartTimeDate = dateFormatter.date(from: entry.start) {
                    var entryEndTimeDate: Date

                    if index < basalEntries.count - 1 {
                        let nextEntry = basalEntries[index + 1]
                        if let nextEntryStartTimeDate = dateFormatter.date(from: nextEntry.start) {
                            let timeDifference = nextEntryStartTimeDate.timeIntervalSince(entryStartTimeDate)
                            entryEndTimeDate = entryStartTimeDate.addingTimeInterval(timeDifference)
                        } else {
                            continue
                        }
                    } else {
                        entryEndTimeDate = Date()
                    }
                    // if currenTime is between start and end of basal entry -> basal = currentBasal
                    if let currentTimeDate = dateFormatter.date(from: currentTime) {
                        if currentTimeDate >= entryStartTimeDate, currentTimeDate <= entryEndTimeDate {
                            if let basal = entry.rate as? Decimal {
                                currentBasal = basal
                                break
                            }
                        }
                    }
                }
            }
        }

        func getDeltaBG() {
            let glucose = provider.fetchGlucose()
            guard glucose.count >= 3 else { return }
            let lastGlucose = glucose.first?.glucose ?? 0
            let thirdLastGlucose = glucose[2]
            let delta = Decimal(lastGlucose) - Decimal(thirdLastGlucose.glucose)
            deltaBG = delta
        }

        // CALCULATIONS FOR THE BOLUS CALCULATOR
        func calculateInsulin() -> Decimal {
            var conversion: Decimal = 1.0
            if units == .mmolL {
                conversion = 0.0555
            }
            // insulin needed for the current blood glucose
            let targetDifference = (currentBG - target) * conversion
            targetDifferenceInsulin = targetDifference / isf

            // more or less insulin because of bg trend in the last 15 minutes
            fifteenMinInsulin = (deltaBG * conversion) / isf

            // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
            wholeCobInsulin = cob / carbRatio

            // determine how much the calculator reduces/ increases the bolus because of IOB
            iobInsulinReduction = (-1) * iob

            // adding everything together
            // add a calc for the case that no fifteenMinInsulin is available
            if deltaBG != 0 {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinInsulin)
            } else {
                // add (rare) case that no glucose value is available -> maybe display warning?
                // if no bg is available, ?? sets its value to 0
                if currentBG == 0 {
                    wholeCalc = (iobInsulinReduction + wholeCobInsulin)
                } else {
                    wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
                }
            }
            // rounding
            let wholeCalcAsDouble = Double(wholeCalc)
            roundedWholeCalc = Decimal(round(100 * wholeCalcAsDouble) / 100)

            // apply custom factor at the end of the calculations
            let result = wholeCalc * fraction

            // apply custom factor if fatty meal toggle in bolus calc config settings is on and the box for fatty meals is checked (in RootView)
            if useFattyMealCorrectionFactor {
                insulinCalculated = result * fattyMealFactor
            } else if useSuperBolus {
                superBolusInsulin = sweetMealFactor * currentBasal
                insulinCalculated = wholeCalc + superBolusInsulin
            } else {
                insulinCalculated = result
            }

            // display no negative insulinCalculated
            insulinCalculated = max(insulinCalculated, 0)
            let insulinCalculatedAsDouble = Double(insulinCalculated)
            roundedInsulinCalculated = Decimal(round(100 * insulinCalculatedAsDouble) / 100)
            insulinCalculated = min(insulinCalculated, maxBolus)

            return apsManager
                .roundBolus(amount: max(insulinCalculated, 0))
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

        func setupInsulinRequired() {
            DispatchQueue.main.async {
                self.insulinRequired = self.provider.suggestion?.insulinReq ?? 0

                var conversion: Decimal = 1.0
                if self.units == .mmolL {
                    conversion = 0.0555
                }

                self.evBG = self.provider.suggestion?.eventualBG ?? 0
                self.insulin = self.provider.suggestion?.insulinForManualBolus ?? 0
                self.target = self.provider.suggestion?.current_target ?? 0
                self.isf = self.provider.suggestion?.isf ?? 0
                self.iob = self.provider.suggestion?.iob ?? 0
                self.currentBG = (self.provider.suggestion?.bg ?? 0)
                self.cob = self.provider.suggestion?.cob ?? 0
                self.basal = self.provider.suggestion?.rate ?? 0
                self.carbRatio = self.provider.suggestion?.carbRatio ?? 0

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

                if self.useCalc {
                    self.getCurrentBasal()
                    self.getDeltaBG()
                    self.insulinCalculated = self.calculateInsulin()
                }
            }
        }

        func backToCarbsView(complexEntry: Bool, _ id: String, override: Bool) {
            delete(deleteTwice: complexEntry, id: id)
            showModal(for: .addCarbs(editMode: complexEntry, override: override))
        }

        func delete(deleteTwice: Bool, id: String) {
            if deleteTwice {
                // DispatchQueue.safeMainSync {
                nsManager.deleteCarbs(
                    at: id, isFPU: nil, fpuID: nil, syncID: id
                )
                nsManager.deleteCarbs(
                    at: id + ".fpu", isFPU: nil, fpuID: nil, syncID: id
                )
                // }
            } else {
                nsManager.deleteCarbs(
                    at: id, isFPU: nil, fpuID: nil, syncID: id
                )
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
