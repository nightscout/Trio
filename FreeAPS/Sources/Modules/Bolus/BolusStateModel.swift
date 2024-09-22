import Combine
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

        @Published var lowGlucose: Decimal = 70
        @Published var highGlucose: Decimal = 180

        @Published var predictions: Predictions?
        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var units: GlucoseUnits = .mgdL
        @Published var threshold: Decimal = 0
        @Published var maxBolus: Decimal = 0
        var maxExternal: Decimal { maxBolus * 3 }
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
        @Published var basal: Decimal = 0
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var useFattyMealCorrectionFactor: Bool = false
        @Published var displayPresets: Bool = true

        @Published var currentBasal: Decimal = 0
        @Published var currentCarbRatio: Decimal = 0
        @Published var currentBGTarget: Decimal = 0
        @Published var currentISF: Decimal = 0

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
        @Published var maxFat: Decimal = 0
        @Published var maxProtein: Decimal = 0

        @Published var id_: String = ""
        @Published var summary: String = ""

        @Published var externalInsulin: Bool = false
        @Published var showInfo: Bool = false
        @Published var glucoseFromPersistence: [GlucoseStored] = []
        @Published var determination: [OrefDetermination] = []
        @Published var preprocessedData: [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] = []
        @Published var predictionsForChart: Predictions?
        @Published var simulatedDetermination: Determination?
        @Published var determinationObjectIDs: [NSManagedObjectID] = []

        @Published var minForecast: [Int] = []
        @Published var maxForecast: [Int] = []
        @Published var minCount: Int = 12 // count of Forecasts drawn in 5 min distances, i.e. 12 means a min of 1 hour
        @Published var forecastDisplayType: ForecastDisplayType = .cone
        @Published var isSmoothingEnabled: Bool = false
        @Published var stops: [Gradient.Stop] = []

        let now = Date.now

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext
        let backgroundContext = CoreDataStack.shared.newTaskContext()

        private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
        private var subscriptions = Set<AnyCancellable>()

        typealias PumpEvent = PumpEventStored.EventType

        override func subscribe() {
            coreDataPublisher =
                changedObjectsOnManagedObjectContextDidSavePublisher()
                    .receive(on: DispatchQueue.global(qos: .background))
                    .share()
                    .eraseToAnyPublisher()
            setupBolusStateConcurrently()
        }

        private func setupBolusStateConcurrently() {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        self.registerHandlers()
                    }
                    group.addTask {
                        self.registerSubscribers()
                    }
                    group.addTask {
                        self.setupGlucoseArray()
                    }
                    group.addTask {
                        self.setupDeterminationsAndForecasts()
                    }
                    group.addTask {
                        await self.setupSettings()
                    }
                    group.addTask {
                        self.registerObservers()
                    }

                    if self.waitForSuggestionInitial {
                        group.addTask {
                            let isDetermineBasalSuccessful = await self.apsManager.determineBasal()
                            if !isDetermineBasalSuccessful {
                                await MainActor.run {
                                    self.waitForSuggestion = false
                                    self.insulinRequired = 0
                                    self.insulinRecommended = 0
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: - Basal

        private enum SettingType {
            case basal
            case carbRatio
            case bgTarget
            case isf
        }

        func getAllSettingsValues() async {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.getCurrentSettingValue(for: .basal)
                }
                group.addTask {
                    await self.getCurrentSettingValue(for: .carbRatio)
                }
                group.addTask {
                    await self.getCurrentSettingValue(for: .bgTarget)
                }
                group.addTask {
                    await self.getCurrentSettingValue(for: .isf)
                }
                group.addTask {
                    let getMaxBolus = await self.provider.getPumpSettings().maxBolus
                    await MainActor.run {
                        self.maxBolus = getMaxBolus
                    }
                }
            }
        }

        private func setupDeterminationsAndForecasts() {
            Task {
                async let getAllSettingsDefaults: () = getAllSettingsValues()
                async let setupDeterminations: () = setupDeterminationsArray()

                await getAllSettingsDefaults
                await setupDeterminations

                // Determination has updated, so we can use this to draw the initial Forecast Chart
                let forecastData = await mapForecastsForChart()
                await updateForecasts(with: forecastData)
            }
        }

        private func registerObservers() {
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(BolusFailureObserver.self, observer: self)
        }

        @MainActor private func setupSettings() async {
            units = settingsManager.settings.units
            fraction = settings.settings.overrideFactor
            fattyMeals = settings.settings.fattyMeals
            fattyMealFactor = settings.settings.fattyMealFactor
            sweetMeals = settings.settings.sweetMeals
            sweetMealFactor = settings.settings.sweetMealFactor
            displayPresets = settings.settings.displayPresets
            forecastDisplayType = settings.settings.forecastDisplayType
            lowGlucose = units == .mgdL ? settingsManager.settings.low : settingsManager.settings.low.asMmolL
            highGlucose = units == .mgdL ? settingsManager.settings.high : settingsManager.settings.high.asMmolL
            maxCarbs = settings.settings.maxCarbs
            maxFat = settings.settings.maxFat
            maxProtein = settings.settings.maxProtein
            useFPUconversion = settingsManager.settings.useFPUconversion
            isSmoothingEnabled = settingsManager.settings.smoothGlucose
        }

        private func getCurrentSettingValue(for type: SettingType) async {
            let now = Date()
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            dateFormatter.timeZone = TimeZone.current

            let entries: [(start: String, value: Decimal)]

            switch type {
            case .basal:
                let basalEntries = await provider.getBasalProfile()
                entries = basalEntries.map { ($0.start, $0.rate) }
            case .carbRatio:
                let carbRatios = await provider.getCarbRatios()
                entries = carbRatios.schedule.map { ($0.start, $0.ratio) }
            case .bgTarget:
                let bgTargets = await provider.getBGTarget()
                entries = bgTargets.targets.map { ($0.start, $0.low) }
            case .isf:
                let isfValues = await provider.getISFValues()
                entries = isfValues.sensitivities.map { ($0.start, $0.sensitivity) }
            }

            for (index, entry) in entries.enumerated() {
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
                if index < entries.count - 1,
                   let nextEntryTime = dateFormatter.date(from: entries[index + 1].start)
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
                        switch type {
                        case .basal:
                            currentBasal = entry.value
                        case .carbRatio:
                            currentCarbRatio = entry.value
                        case .bgTarget:
                            currentBGTarget = entry.value
                        case .isf:
                            currentISF = entry.value
                        }
                    }
                    return
                }
            }
        }

        // MARK: CALCULATIONS FOR THE BOLUS CALCULATOR

        /// Calculate insulin recommendation
        func calculateInsulin() -> Decimal {
            let isfForCalculation = units == .mmolL ? isf.asMgdL : isf

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

        func invokeTreatmentsTask() {
            Task {
                await MainActor.run {
                    self.addButtonPressed = true
                }
                let isInsulinGiven = amount > 0
                let isCarbsPresent = carbs > 0
                let isFatPresent = fat > 0
                let isProteinPresent = protein > 0

                if isInsulinGiven {
                    try await handleInsulin(isExternal: externalInsulin)
                } else if isCarbsPresent || isFatPresent || isProteinPresent {
                    await MainActor.run {
                        self.waitForSuggestion = true
                    }
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

        private func handleInsulin(isExternal: Bool) async throws {
            if !isExternal {
                await addPumpInsulin()
            } else {
                await addExternalInsulin()
            }

            await MainActor.run {
                self.waitForSuggestion = true
            }
        }

        func addPumpInsulin() async {
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
                await MainActor.run {
                    self.waitForSuggestion = false
                    if self.addButtonPressed {
                        self.hideModal()
                    }
                }
            }
        }

        // MARK: - EXTERNAL INSULIN

        func addExternalInsulin() async {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            await MainActor.run {
                self.amount = min(self.amount, self.maxBolus * 3)
            }

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
                await MainActor.run {
                    self.waitForSuggestion = false
                    if self.addButtonPressed {
                        self.hideModal()
                    }
                }
            }
        }

        // MARK: - Carbs

        func saveMeal() async {
            guard carbs > 0 || fat > 0 || protein > 0 else { return }

            await MainActor.run {
                self.carbs = min(self.carbs, self.maxCarbs)
                self.fat = min(self.fat, self.maxFat)
                self.protein = min(self.protein, self.maxProtein)
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
            await carbsStorage.storeCarbs(carbsToStore, areFetchedFromRemote: false)

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
        coreDataPublisher?.filterByEntityName("OrefDetermination").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.setupDeterminationsArray()
                await self.updateForecasts()
            }
        }.store(in: &subscriptions)

        // Due to the Batch insert this only is used for observing Deletion of Glucose entries
        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            self.setupGlucoseArray()
        }.store(in: &subscriptions)
    }

    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.setupGlucoseArray()
            }
            .store(in: &subscriptions)
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
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        guard let fetchedResults = results as? [GlucoseStored] else { return [] }

        return await backgroundContext.perform {
            return fetchedResults.map(\.objectID)
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
    private func setupDeterminationsArray() async {
        // Fetch object IDs on a background thread
        let fetchedObjectIDs = await determinationStorage.fetchLastDeterminationObjectID(
            predicate: NSPredicate.predicateFor30MinAgoForDetermination
        )

        // Update determinationObjectIDs on the main thread
        await MainActor.run {
            determinationObjectIDs = fetchedObjectIDs
        }

        let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
            .getNSManagedObject(with: determinationObjectIDs, context: viewContext)

        await updateDeterminationsArray(with: determinationObjects)
    }

    private func mapForecastsForChart() async -> Determination? {
        let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
            .getNSManagedObject(with: determinationObjectIDs, context: backgroundContext)

        return await backgroundContext.perform {
            guard let determinationObject = determinationObjects.first else {
                return nil
            }

            let eventualBG = determinationObject.eventualBG?.intValue

            let forecastsSet = determinationObject.forecasts as? Set<Forecast> ?? []
            let predictions = Predictions(
                iob: forecastsSet.extractValues(for: "iob"),
                zt: forecastsSet.extractValues(for: "zt"),
                cob: forecastsSet.extractValues(for: "cob"),
                uam: forecastsSet.extractValues(for: "uam")
            )

            return Determination(
                id: UUID(),
                reason: "",
                units: 0,
                insulinReq: 0,
                eventualBG: eventualBG,
                sensitivityRatio: 0,
                rate: 0,
                duration: 0,
                iob: 0,
                cob: 0,
                predictions: predictions.isEmpty ? nil : predictions,
                carbsReq: 0,
                temp: nil,
                bg: 0,
                reservoir: 0,
                isf: 0,
                tdd: 0,
                insulin: nil,
                current_target: 0,
                insulinForManualBolus: 0,
                manualBolusErrorString: 0,
                minDelta: 0,
                expectedDelta: 0,
                minGuardBG: 0,
                minPredBG: 0,
                threshold: 0,
                carbRatio: 0,
                received: false
            )
        }
    }

    @MainActor private func updateDeterminationsArray(with objects: [OrefDetermination]) {
        guard let mostRecentDetermination = objects.first else { return }
        determination = objects

        // setup vars for bolus calculation
        insulinRequired = (mostRecentDetermination.insulinReq ?? 0) as Decimal
        evBG = (mostRecentDetermination.eventualBG ?? 0) as Decimal
        insulin = (mostRecentDetermination.insulinForManualBolus ?? 0) as Decimal
        target = (mostRecentDetermination.currentTarget ?? currentBGTarget as NSDecimalNumber) as Decimal
        isf = (mostRecentDetermination.insulinSensitivity ?? currentISF as NSDecimalNumber) as Decimal
        cob = mostRecentDetermination.cob as Int16
        iob = (mostRecentDetermination.iob ?? 0) as Decimal
        basal = (mostRecentDetermination.tempBasal ?? 0) as Decimal
        carbRatio = (mostRecentDetermination.carbRatio ?? currentCarbRatio as NSDecimalNumber) as Decimal
        insulinCalculated = calculateInsulin()
    }
}

extension Bolus.StateModel {
    @MainActor func updateForecasts(with forecastData: Determination? = nil) async {
        if let forecastData = forecastData {
            simulatedDetermination = forecastData
        } else {
            simulatedDetermination = await Task.detached { [self] in
                await apsManager.simulateDetermineBasal(carbs: carbs, iob: amount)
            }.value
        }

        predictionsForChart = simulatedDetermination?.predictions

        let nonEmptyArrays = [
            predictionsForChart?.iob,
            predictionsForChart?.zt,
            predictionsForChart?.cob,
            predictionsForChart?.uam
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        guard !nonEmptyArrays.isEmpty else {
            minForecast = []
            maxForecast = []
            return
        }

        minCount = max(12, nonEmptyArrays.map(\.count).min() ?? 0)
        guard minCount > 0 else { return }

        async let minForecastResult = Task.detached {
            (0 ..< self.minCount).map { index in
                nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }.min() ?? 0
            }
        }.value

        async let maxForecastResult = Task.detached {
            (0 ..< self.minCount).map { index in
                nonEmptyArrays.compactMap { $0.indices.contains(index) ? $0[index] : nil }.max() ?? 0
            }
        }.value

        minForecast = await minForecastResult
        maxForecast = await maxForecastResult
    }
}

private extension Set where Element == Forecast {
    func extractValues(for type: String) -> [Int]? {
        let values = first { $0.type == type }?
            .forecastValues?
            .sorted { $0.index < $1.index }
            .compactMap { Int($0.value) }
        return values?.isEmpty ?? true ? nil : values
    }
}

private extension Predictions {
    var isEmpty: Bool {
        iob == nil && zt == nil && cob == nil && uam == nil
    }
}
