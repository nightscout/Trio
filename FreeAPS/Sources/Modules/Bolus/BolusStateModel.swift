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
        @Injected() var determinationStorage: DeterminationStorage!

        @Published var lowGlucose: Decimal = 4 / 0.0555
        @Published var highGlucose: Decimal = 10 / 0.0555

        @Published var predictions: Predictions?
        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var units: GlucoseUnits = .mgdL
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
        @Published var selection: MealPresetStored?
        @Published var summation: [String] = []
        @Published var maxCarbs: Decimal = 0

        @Published var id_: String = ""
        @Published var summary: String = ""
        @Published var skipBolus: Bool = false

        @Published var externalInsulin: Bool = false
        @Published var showInfo: Bool = false
        @Published var glucoseFromPersistence: [GlucoseStored] = []
        @Published var determination: [OrefDetermination] = []
        @Published var preprocessedData: [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] = []
        @Published var predictionsForChart: Predictions?
        @Published var simulatedDetermination: Determination?

        @Published var minForecast: [Int] = []
        @Published var maxForecast: [Int] = []

        let now = Date.now

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
        let backgroundContext = CoreDataStack.shared.newTaskContext()

        private var coreDataObserver: CoreDataObserver?

        typealias PumpEvent = PumpEventStored.EventType

        override func subscribe() {
            setupGlucoseNotification()
            coreDataObserver = CoreDataObserver()
            registerHandlers()

            Task {
                await updateForecasts()
            }

            setupGlucoseArray()
            setupDeterminationsArray()

            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(BolusFailureObserver.self, observer: self)
            units = settingsManager.settings.units
            percentage = settingsManager.settings.insulinReqPercentage
            maxBolus = provider.pumpSettings().maxBolus
            // added
            fraction = settings.settings.overrideFactor
            useCalc = settings.settings.useCalc
            fattyMeals = settings.settings.fattyMeals
            fattyMealFactor = settings.settings.fattyMealFactor
            sweetMeals = settings.settings.sweetMeals
            sweetMealFactor = settings.settings.sweetMealFactor
            displayPresets = settings.settings.displayPresets

            lowGlucose = settingsManager.settings.low
            highGlucose = settingsManager.settings.high

            maxCarbs = settings.settings.maxCarbs
            skipBolus = settingsManager.settings.skipBolusScreenAfterCarbs
            useFPUconversion = settingsManager.settings.useFPUconversion

            if waitForSuggestionInitial {
                Task {
                    let ok = await apsManager.determineBasal()
                    if !ok {
                        self.waitForSuggestion = false
                        self.insulinRequired = 0
                        self.insulinRecommended = 0
                    }
                }
            }
        }

        // MARK: - Basal

        func getCurrentBasal() async {
            let basalEntries = provider.getProfile()
            let now = Date()
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            dateFormatter.timeZone = TimeZone.current

            for (index, entry) in basalEntries.enumerated() {
                guard let entryTime = dateFormatter.date(from: entry.start) else {
                    print("Invalid entry start time: \(entry.start)")
                    continue
                }

                let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
                let entryStartTime = calendar.date(
                    bySettingHour: entryComponents.hour!,
                    minute: entryComponents.minute!,
                    second: entryComponents.second!,
                    of: now
                )!

                let entryEndTime: Date
                if index < basalEntries.count - 1,
                   let nextEntryTime = dateFormatter.date(from: basalEntries[index + 1].start)
                {
                    let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                    entryEndTime = calendar.date(
                        bySettingHour: nextEntryComponents.hour!,
                        minute: nextEntryComponents.minute!,
                        second: nextEntryComponents.second!,
                        of: now
                    )!
                } else {
                    entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                }

                if now >= entryStartTime, now < entryEndTime {
                    await MainActor.run {
                        currentBasal = entry.rate
                    }
                    break
                }
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

        // MARK: - Button tasks

        @MainActor func invokeTreatmentsTask() {
            Task {
                addButtonPressed = true
                let isInsulinGiven = amount > 0
                let isCarbsPresent = carbs > 0
                let isFatPresent = fat > 0
                let isProteinPresent = protein > 0

                if isInsulinGiven {
                    try await handleInsulin(isExternal: externalInsulin)
                } else if isCarbsPresent || isFatPresent || isProteinPresent {
                    waitForSuggestion = true
                } else {
                    hideModal()
                    return
                }

                await saveMeal()

                // if glucose data is stale end the custom loading animation by hiding the modal
                guard glucoseStorage.isGlucoseDataFresh(glucoseFromPersistence.first?.date) else {
                    waitForSuggestion = false
                    return hideModal()
                }
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

            let maxAmount = Double(min(amount, maxBolus))

            do {
                let authenticated = try await unlockmanager.unlock()
                if authenticated {
                    await apsManager.enactBolus(amount: maxAmount, isSMB: false)
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

        private func savePumpInsulin(amount _: Decimal) {
            backgroundContext.perform {
                // create pump event
                let newPumpEvent = PumpEventStored(context: self.backgroundContext)
                newPumpEvent.timestamp = Date()
                newPumpEvent.type = PumpEvent.bolus.rawValue

                // create bolus entry and specify relationship to pump event
                let newBolusEntry = BolusStored(context: self.backgroundContext)
                newBolusEntry.pumpEvent = newPumpEvent
                newBolusEntry.amount = self.amount as NSDecimalNumber
                newBolusEntry.isExternal = false
                newBolusEntry.isSMB = false

                do {
                    guard self.backgroundContext.hasChanges else { return }
                    try self.backgroundContext.save()
                } catch let error as NSError {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Bolus with error: \(error.userInfo)"
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
                    // store external dose to pump history
                    await pumpHistoryStorage.storeExternalInsulinEvent(amount: amount, timestamp: date)
                    // perform determine basal sync
                    await apsManager.determineBasalSync()
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

        // MARK: - Carbs

        @MainActor func saveMeal() async {
            guard carbs > 0 || fat > 0 || protein > 0 else { return }

            await MainActor.run {
                self.carbs = min(self.carbs, self.maxCarbs)
                self.id_ = UUID().uuidString
            }

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
            await carbsStorage.storeCarbs(carbsToStore)

            if carbs > 0 || fat > 0 || protein > 0 {
                // only perform determine basal sync if the user doesn't use the pump bolus, otherwise the enact bolus func in the APSManger does a sync
                if amount <= 0 {
                    await apsManager.determineBasalSync()
                }
            }
        }

        // MARK: - Presets

        func deletePreset() {
            if selection != nil {
                viewContext.delete(selection!)

                do {
                    guard viewContext.hasChanges else { return }
                    try viewContext.save()
                } catch {
                    print(error.localizedDescription)
                }
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
            var presetArray = [MealPresetStored]()

            // TODO: purge Jons code
            viewContext.performAndWait {
                let requestPresets = MealPresetStored.fetchRequest() as NSFetchRequest<MealPresetStored>
                try? presetArray = viewContext.fetch(requestPresets)
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

extension Bolus.StateModel {
    private func registerHandlers() {
        coreDataObserver?.registerHandler(for: "OrefDetermination") { [weak self] in
            guard let self = self else { return }
            self.setupDeterminationsArray()
        }

        // Due to the Batch insert this only is used for observing Deletion of Glucose entries
        coreDataObserver?.registerHandler(for: "GlucoseStored") { [weak self] in
            guard let self = self else { return }
            self.setupGlucoseArray()
        }
    }

    private func setupGlucoseNotification() {
        /// custom notification that is sent when a batch insert of glucose objects is done
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatchInsert),
            name: .didPerformBatchInsert,
            object: nil
        )
    }

    @objc private func handleBatchInsert() {
        setupGlucoseArray()
    }
}

// MARK: - Setup Glucose and Determinations

extension Bolus.StateModel {
    // Glucose
    private func setupGlucoseArray() {
        Task {
            let ids = await self.fetchGlucose()
            let glucoseObjects: [GlucoseStored] = await CoreDataStack.shared.getNSManagedObject(with: ids, context: viewContext)
            await updateGlucoseArray(with: glucoseObjects)
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateForFourHoursAgo,
            key: "date",
            ascending: false,
            fetchLimit: 48
        )

        return await backgroundContext.perform {
            return results.map(\.objectID)
        }
    }

    @MainActor private func updateGlucoseArray(with objects: [GlucoseStored]) {
        glucoseFromPersistence = objects

        let lastGlucose = glucoseFromPersistence.first?.glucose ?? 0
        let thirdLastGlucose = glucoseFromPersistence.dropFirst(2).first?.glucose ?? 0
        let delta = Decimal(lastGlucose) - Decimal(thirdLastGlucose)

        currentBG = Decimal(lastGlucose)
        deltaBG = delta
    }

    // Determinations
    private func setupDeterminationsArray() {
        Task {
            let ids = await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.predicateFor30MinAgoForDetermination
            )
            let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
                .getNSManagedObject(with: ids, context: viewContext)

            async let updateDetermination: () = updateDeterminationsArray(with: determinationObjects)
            async let getCurrentBasal: () = getCurrentBasal()
            async let updateForecasts: () = updateForecasts()

            await updateForecasts
            await getCurrentBasal
            await updateDetermination
        }
    }

    @MainActor private func updateDeterminationsArray(with objects: [OrefDetermination]) {
        guard let mostRecentDetermination = objects.first else { return }
        determination = objects

        // setup vars for bolus calculation
        insulinRequired = (mostRecentDetermination.insulinReq ?? 0) as Decimal
        evBG = (mostRecentDetermination.eventualBG ?? 0) as Decimal
        insulin = (mostRecentDetermination.insulinForManualBolus ?? 0) as Decimal
        target = (mostRecentDetermination.currentTarget ?? 100) as Decimal
        isf = (mostRecentDetermination.insulinSensitivity ?? 0) as Decimal
        cob = mostRecentDetermination.cob as Int16
        iob = (mostRecentDetermination.iob ?? 0) as Decimal
        basal = (mostRecentDetermination.tempBasal ?? 0) as Decimal
        carbRatio = (mostRecentDetermination.carbRatio ?? 0) as Decimal
        insulinCalculated = calculateInsulin()
    }
}

extension Bolus.StateModel {
    func calculateForecasts(predictions: Predictions?) -> ([Int], [Int]) {
        let iob: [Int] = predictions?.iob ?? []
        let zt: [Int] = predictions?.zt ?? []
        let cob: [Int] = predictions?.cob ?? []
        let uam: [Int] = predictions?.uam ?? []

        // Filter out the empty arrays and find the maximum length of the remaining arrays
        let nonEmptyArrays: [[Int]] = [iob, zt, cob, uam].filter { !$0.isEmpty }
        guard !nonEmptyArrays.isEmpty, let maxCount = nonEmptyArrays.map(\.count).max(), maxCount > 0 else {
            return ([], [])
        }

        let minForecast = (0 ..< maxCount).map { index -> Int in
            let valuesAtCurrentIndex = nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }
            return valuesAtCurrentIndex.min() ?? 0
        }

        let maxForecast = (0 ..< maxCount).map { index -> Int in
            let valuesAtCurrentIndex = nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }
            return valuesAtCurrentIndex.max() ?? 0
        }

        return (minForecast, maxForecast)
    }

    @MainActor func updateForecasts() async {
        simulatedDetermination = await apsManager.simulateDetermineBasal(carbs: carbs, iob: amount)
        predictionsForChart = simulatedDetermination?.predictions

        let iob: [Int] = predictionsForChart?.iob ?? []
        let zt: [Int] = predictionsForChart?.zt ?? []
        let cob: [Int] = predictionsForChart?.cob ?? []
        let uam: [Int] = predictionsForChart?.uam ?? []

        // Filter out the empty arrays and find the maximum length of the remaining arrays
        let nonEmptyArrays: [[Int]] = [iob, zt, cob, uam].filter { !$0.isEmpty }
        guard !nonEmptyArrays.isEmpty, let maxCount = nonEmptyArrays.map(\.count).max(), maxCount > 0 else {
            minForecast = []
            maxForecast = []
            return
        }

        minForecast = (0 ..< maxCount).map { index -> Int in
            let valuesAtCurrentIndex = nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }
            return valuesAtCurrentIndex.min() ?? 0
        }

        maxForecast = (0 ..< maxCount).map { index -> Int in
            let valuesAtCurrentIndex = nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }
            return valuesAtCurrentIndex.max() ?? 0
        }
    }
}
