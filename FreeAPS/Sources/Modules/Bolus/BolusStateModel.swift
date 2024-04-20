import CoreData
import Foundation
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
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var glucoseStorage: GlucoseStorage!

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
        @Published var evBG: Decimal = 0
        @Published var insulin: Decimal = 0
        @Published var isf: Decimal = 0
        @Published var error: Bool = false
        @Published var minGuardBG: Decimal = 0
        @Published var minDelta: Decimal = 0
        @Published var expectedDelta: Decimal = 0
        @Published var minPredBG: Decimal = 0
        @Published var waitForSuggestion: Bool = false
        @Published var carbRatio: Decimal = 0

        @Published var addButtonPressed: Bool = false

        var waitForSuggestionInitial: Bool = false

        // added for bolus calculator
        @Published var target: Decimal = 0
        @Published var cob: Int16 = 0
        @Published var iob: Decimal = 0

        @Published var currentBG: Decimal = 0
        @Published var fifteenMinInsulin: Decimal = 0
        @Published var deltaBG: Decimal = 0
        @Published var targetDifferenceInsulin: Decimal = 0
        @Published var targetDifference: Decimal = 0
        @Published var wholeCob: Decimal = 0
        @Published var wholeCobInsulin: Decimal = 0
        @Published var iobInsulinReduction: Decimal = 0
        @Published var wholeCalc: Decimal = 0
        @Published var insulinCalculated: Decimal = 0
        @Published var fraction: Decimal = 0
        @Published var useCalc: Bool = false
        @Published var basal: Decimal = 0
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var useFattyMealCorrectionFactor: Bool = false
        @Published var displayPresets: Bool = true

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

        @Published var date = Date()

        @Published var carbsRequired: Decimal?
        @Published var useFPUconversion: Bool = false
        @Published var dish: String = ""
        @Published var selection: Presets?
        @Published var summation: [String] = []
        @Published var maxCarbs: Decimal = 0

        @Published var id_: String = ""
        @Published var summary: String = ""
        @Published var skipBolus: Bool = false

        @Published var externalInsulin: Bool = false
        @Published var showInfo: Bool = false

        @Published var glucoseFromPersistence: [GlucoseStored] = []
        @Published var determination: [OrefDetermination] = []

        let now = Date.now

        let context = CoreDataStack.shared.viewContext

        override func subscribe() {
            fetchGlucose()
            fetchDetermination()
            setupInsulinRequired()
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(BolusFailureObserver.self, observer: self)
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
            displayPresets = settings.settings.displayPresets

            carbsRequired = provider.suggestion?.carbsReq
            maxCarbs = settings.settings.maxCarbs
            skipBolus = settingsManager.settings.skipBolusScreenAfterCarbs
            useFPUconversion = settingsManager.settings.useFPUconversion

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

        // MARK: - Basal

        func getCurrentBasal() {
            let basalEntries = provider.getProfile()
            let now = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"

            // iterate over basal entries
            for (index, entry) in basalEntries.enumerated() {
                guard let entryStartTime = dateFormatter.date(from: entry.start) else { continue }

                let entryEndTime: Date
                if index < basalEntries.count - 1,
                   let nextEntryStartTime = dateFormatter.date(from: basalEntries[index + 1].start)
                {
                    // end of current entry should equal start of next entry
                    entryEndTime = nextEntryStartTime
                } else {
                    // if it is the last entry use current time as end of entry
                    entryEndTime = now
                }

                // proof if current time is between start and end of entry
                if now >= entryStartTime, now < entryEndTime {
                    currentBasal = entry.rate
                    break
                }
            }
        }

        // MARK: - Glucose

        private func fetchGlucose() {
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
            fetchRequest.predicate = NSPredicate.predicateFor30MinAgo
            fetchRequest.fetchLimit = 3
            do {
                glucoseFromPersistence = try context.fetch(fetchRequest)

                let lastGlucose = glucoseFromPersistence.first?.glucose ?? 0
                let thirdLastGlucose = glucoseFromPersistence.last?.glucose ?? 0
                let delta = Decimal(lastGlucose) - Decimal(thirdLastGlucose)

                currentBG = Decimal(lastGlucose)
                deltaBG = delta

            } catch {
                debugPrint("Bolus State: \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to fetch glucose")
            }
        }

        private func fetchDetermination() {
            do {
                determination = try context.fetch(OrefDetermination.fetch(NSPredicate.predicateFor30MinAgoForDetermination))
                debugPrint(
                    "Bolus State: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) fetched determinations"
                )
            } catch {
                debugPrint(
                    "Bolus State: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to fetch determinations"
                )
            }
        }

        // MARK: CALCULATIONS FOR THE BOLUS CALCULATOR

        /// Calculate insulin recommendation
        func calculateInsulin() -> Decimal {
            // ensure that isf is in mg/dL
            var conversion: Decimal {
                units == .mmolL ? 0.0555 : 1
            }
            let isfForCalculation = isf / conversion

            // insulin needed for the current blood glucose
            targetDifference = currentBG - target
            targetDifferenceInsulin = targetDifference / isfForCalculation

            // more or less insulin because of bg trend in the last 15 minutes
            fifteenMinInsulin = deltaBG / isfForCalculation

            // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
            wholeCob = Decimal(cob) + carbs
            wholeCobInsulin = wholeCob / carbRatio

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

            // apply custom factor at the end of the calculations
            let result = wholeCalc * fraction

            // apply custom factor if fatty meal toggle in bolus calc config settings is on and the box for fatty meals is checked (in RootView)
            if useFattyMealCorrectionFactor {
                insulinCalculated = result * fattyMealFactor
            } else if useSuperBolus {
                superBolusInsulin = sweetMealFactor * currentBasal
                insulinCalculated = result + superBolusInsulin
            } else {
                insulinCalculated = result
            }
            // display no negative insulinCalculated
            insulinCalculated = max(insulinCalculated, 0)
            insulinCalculated = min(insulinCalculated, maxBolus)

            guard let apsManager = apsManager else {
                debug(.apsManager, "APSManager could not be gracefully unwrapped")
                return insulinCalculated
            }

            return apsManager.roundBolus(amount: insulinCalculated)
        }

        func setupInsulinRequired() {
            DispatchQueue.main.async {
                self.insulinRequired = (self.determination.first?.insulinReq ?? 0) as Decimal
                self.evBG = (self.determination.first?.eventualBG ?? 0) as Decimal
                self.insulin = (self.determination.first?.insulinForManualBolus ?? 0) as Decimal
                self.target = (self.determination.first?.currentTarget ?? 100) as Decimal
                self.isf = (self.determination.first?.insulinSensitivity ?? 0) as Decimal
                self.iob = (self.determination.first?.iob ?? 0) as Decimal
                self.cob = (self.determination.first?.cob ?? 0) as Int16
                self.basal = (self.determination.first?.tempBasal ?? 0) as Decimal
                self.carbRatio = (self.determination.first?.carbRatio ?? 0) as Decimal
                self.getCurrentBasal()
                self.insulinCalculated = self.calculateInsulin()
            }
        }

        // MARK: - Button tasks

        @MainActor func invokeTreatmentsTask() {
            Task {
                let isInsulinGiven = amount > 0
                let isCarbsPresent = carbs > 0

                if isInsulinGiven {
                    try await handleInsulin(isExternal: externalInsulin)
                } else if isCarbsPresent {
                    waitForSuggestion = true
                } else {
                    hideModal()
                    return
                }

                saveMeal()
                addButtonPressed = true

                // if glucose data is stale end the custom loading animation by hiding the modal
//                guard glucoseOfLast20Min.first?.date ?? now >= Date().addingTimeInterval(-12.minutes.timeInterval) else {
//                    return hideModal()
//                }
            }
        }

        // MARK: - Insulin

        @MainActor private func handleInsulin(isExternal: Bool) async throws {
            if !isExternal {
                await addPumpInsulin()
            } else {
                await addExternalInsulin()
            }
            waitForSuggestion = true
        }

        @MainActor func addPumpInsulin() async {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            let maxAmount = Double(min(amount, provider.pumpSettings().maxBolus))

            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    apsManager.enactBolus(amount: maxAmount, isSMB: false)
                    savePumpInsulin(amount: amount)
                } else {
                    print("authentication failed")
                }
            } catch {
                print("authentication error for pump bolus: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.waitForSuggestion = false
                    if self.addButtonPressed {
                        self.hideModal()
                    }
                }
            }
        }

        private func savePumpInsulin(amount: Decimal) {
            let newItem = InsulinStored(context: context)
            newItem.id = UUID()
            newItem.amount = amount as NSDecimalNumber
            newItem.date = Date()
            newItem.external = false
            newItem.isSMB = false
            context.perform {
                do {
                    try self.context.save()
                    debugPrint(
                        "Bolus State: \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) saved pump insulin to core data"
                    )
                } catch {
                    debugPrint(
                        "Bolus State: \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to save pump insulin to core data"
                    )
                }
            }
        }

        // MARK: - EXTERNAL INSULIN

        @MainActor func addExternalInsulin() async {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            amount = min(amount, maxBolus * 3)

            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    storeExternalInsulinEvent()
                } else {
                    print("authentication failed")
                }
            } catch {
                print("authentication error for external insulin: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.waitForSuggestion = false
                    if self.addButtonPressed {
                        self.hideModal()
                    }
                }
            }
        }

        private func storeExternalInsulinEvent() {
            pumpHistoryStorage.storeEvents(
                [
                    PumpHistoryEvent(
                        id: UUID().uuidString,
                        type: .bolus,
                        timestamp: date,
                        amount: amount,
                        duration: nil,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil,
                        isExternal: true
                    )
                ]
            )
            debug(.default, "External insulin saved to pumphistory.json")

            // save to core data asynchronously
            context.perform {
                let newItem = InsulinStored(context: self.context)
                newItem.amount = self.amount as NSDecimalNumber
                newItem.date = Date()
                newItem.external = true
                newItem.isSMB = false
                do {
                    try self.context.save()
                    debugPrint(
                        "Bolus State: \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) saved carbs to core data"
                    )
                } catch {
                    debugPrint(
                        "Bolus State: \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to save carbs to core data"
                    )
                }
            }

            // perform determine basal sync
            apsManager.determineBasalSync()
        }

        // MARK: - Carbs

        // we need to also fetch the data after we have saved them in order to update the array and the UI because of the MVVM Architecture

        func saveMeal() {
            guard carbs > 0 || fat > 0 || protein > 0 else { return }
            carbs = min(carbs, maxCarbs)
            id_ = UUID().uuidString

            let carbsToStore = [CarbsEntry(
                id: id_,
                createdAt: now,
                actualDate: date,
                carbs: carbs,
                fat: fat,
                protein: protein,
                note: note,
                enteredBy: CarbsEntry.manual,
                isFPU: false, fpuID: UUID().uuidString
            )]
            carbsStorage.storeCarbs(carbsToStore)

            if carbs > 0 {
                // only perform determine basal sync if the user doesn't use the pump bolus, otherwise the enact bolus func in the APSManger does a sync
                if amount <= 0 {
                    apsManager.determineBasalSync()
                }
            }
        }

        // MARK: - Presets

        func deletePreset() {
            if selection != nil {
                try? context.delete(selection!)
                try? context.save()
                carbs = 0
                fat = 0
                protein = 0
            }
            selection = nil
        }

        func removePresetFromNewMeal() {
            let a = summation.firstIndex(where: { $0 == selection?.dish! })
            if a != nil, summation[a ?? 0] != "" {
                summation.remove(at: a!)
            }
        }

        func addPresetToNewMeal() {
            let test: String = selection?.dish ?? "dontAdd"
            if test != "dontAdd" {
                summation.append(test)
            }
        }

        func addNewPresetToWaitersNotepad(_ dish: String) {
            summation.append(dish)
        }

        func addToSummation() {
            summation.append(selection?.dish ?? "")
        }

        func waitersNotepad() -> String {
            var filteredArray = summation.filter { !$0.isEmpty }

            if carbs == 0, protein == 0, fat == 0 {
                filteredArray = []
            }

            guard filteredArray != [] else {
                return ""
            }
            var carbs_: Decimal = 0.0
            var fat_: Decimal = 0.0
            var protein_: Decimal = 0.0
            var presetArray = [Presets]()

            context.performAndWait {
                let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
                try? presetArray = context.fetch(requestPresets)
            }
            var waitersNotepad = [String]()
            var stringValue = ""

            for each in filteredArray {
                let countedSet = NSCountedSet(array: filteredArray)
                let count = countedSet.count(for: each)
                if each != stringValue {
                    waitersNotepad.append("\(count) \(each)")
                }
                stringValue = each

                for sel in presetArray {
                    if sel.dish == each {
                        carbs_ += (sel.carbs)! as Decimal
                        fat_ += (sel.fat)! as Decimal
                        protein_ += (sel.protein)! as Decimal
                        break
                    }
                }
            }
            let extracarbs = carbs - carbs_
            let extraFat = fat - fat_
            let extraProtein = protein - protein_
            var addedString = ""

            if extracarbs > 0, filteredArray.isNotEmpty {
                addedString += "Additional carbs: \(extracarbs) ,"
            } else if extracarbs < 0 { addedString += "Removed carbs: \(extracarbs) " }

            if extraFat > 0, filteredArray.isNotEmpty {
                addedString += "Additional fat: \(extraFat) ,"
            } else if extraFat < 0 { addedString += "Removed fat: \(extraFat) ," }

            if extraProtein > 0, filteredArray.isNotEmpty {
                addedString += "Additional protein: \(extraProtein) ,"
            } else if extraProtein < 0 { addedString += "Removed protein: \(extraProtein) ," }

            if addedString != "" {
                waitersNotepad.append(addedString)
            }
            var waitersNotepadString = ""

            if waitersNotepad.count == 1 {
                waitersNotepadString = waitersNotepad[0]
            } else if waitersNotepad.count > 1 {
                for each in waitersNotepad {
                    if each != waitersNotepad.last {
                        waitersNotepadString += " " + each + ","
                    } else { waitersNotepadString += " " + each }
                }
            }
            return waitersNotepadString
        }
    }
}

extension Bolus.StateModel: DeterminationObserver, BolusFailureObserver {
    func determinationDidUpdate(_: Determination) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
            if self.addButtonPressed {
                self.hideModal()
            }
        }
        setupInsulinRequired()
    }

    func bolusDidFail() {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
            if self.addButtonPressed {
                self.hideModal()
            }
        }
    }
}
