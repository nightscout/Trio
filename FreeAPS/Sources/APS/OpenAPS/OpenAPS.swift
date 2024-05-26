import Combine
import CoreData
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage

    let context = CoreDataStack.shared.persistentContainer.newBackgroundContext()

    let jsonConverter = JSONConverter()

    init(storage: FileStorage) {
        self.storage = storage
    }

    // Helper function to convert a Decimal? to NSDecimalNumber?
    func decimalToNSDecimalNumber(_ value: Decimal?) -> NSDecimalNumber? {
        guard let value = value else { return nil }
        return NSDecimalNumber(decimal: value)
    }

    // Use the helper function for cleaner code
    func processDetermination(_ determination: Determination) {
        context.perform {
            let newOrefDetermination = OrefDetermination(context: self.context)
            newOrefDetermination.id = UUID()

            newOrefDetermination.totalDailyDose = self.decimalToNSDecimalNumber(determination.tdd)
            newOrefDetermination.insulinSensitivity = self.decimalToNSDecimalNumber(determination.isf)
            newOrefDetermination.currentTarget = self.decimalToNSDecimalNumber(determination.current_target)
            newOrefDetermination.eventualBG = determination.eventualBG.map(NSDecimalNumber.init)
            newOrefDetermination.deliverAt = determination.deliverAt
            newOrefDetermination.insulinForManualBolus = self.decimalToNSDecimalNumber(determination.insulinForManualBolus)
            newOrefDetermination.carbRatio = self.decimalToNSDecimalNumber(determination.carbRatio)
            newOrefDetermination.glucose = self.decimalToNSDecimalNumber(determination.bg)
            newOrefDetermination.reservoir = self.decimalToNSDecimalNumber(determination.reservoir)
            newOrefDetermination.insulinReq = self.decimalToNSDecimalNumber(determination.insulinReq)
            newOrefDetermination.temp = determination.temp?.rawValue ?? "absolute"
            newOrefDetermination.rate = self.decimalToNSDecimalNumber(determination.rate)
            newOrefDetermination.reason = determination.reason
            newOrefDetermination.duration = Int16(determination.duration ?? 0)
            newOrefDetermination.iob = self.decimalToNSDecimalNumber(determination.iob)
            newOrefDetermination.threshold = self.decimalToNSDecimalNumber(determination.threshold)
            newOrefDetermination.minDelta = self.decimalToNSDecimalNumber(determination.minDelta)
            newOrefDetermination.sensitivityRatio = self.decimalToNSDecimalNumber(determination.sensitivityRatio)
            newOrefDetermination.expectedDelta = self.decimalToNSDecimalNumber(determination.expectedDelta)
            newOrefDetermination.cob = Int16(Int(determination.cob ?? 0))
            newOrefDetermination.manualBolusErrorString = self.decimalToNSDecimalNumber(determination.manualBolusErrorString)
            newOrefDetermination.tempBasal = determination.insulin?.temp_basal.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.scheduledBasal = determination.insulin?.scheduled_basal.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.bolus = determination.insulin?.bolus.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.smbToDeliver = determination.units.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.carbsRequired = Int16(Int(determination.carbsReq ?? 0))

            if let predictions = determination.predictions {
                ["iob": predictions.iob, "zt": predictions.zt, "cob": predictions.cob, "uam": predictions.uam]
                    .forEach { type, values in
                        if let values = values {
                            let forecast = Forecast(context: self.context)
                            forecast.id = UUID()
                            forecast.type = type
                            forecast.date = Date()
                            forecast.orefDetermination = newOrefDetermination

                            for (index, value) in values.enumerated() {
                                let forecastValue = ForecastValue(context: self.context)
                                forecastValue.index = Int32(index)
                                forecastValue.value = Int32(value)
                                forecast.addToForecastValues(forecastValue)
                            }
                            newOrefDetermination.addToForecasts(forecast)
                        }
                    }
            }

            self.attemptToSaveContext()
        }
    }

    func attemptToSaveContext() {
        do {
            guard context.hasChanges else { return }
            try context.save()
        } catch {
            print(error.localizedDescription)
        }
    }

    // fetch glucose to pass it to the meal function and to determine basal
    private func fetchAndProcessGlucose() -> String {
        var glucoseAsJSON: String?

        context.performAndWait {
            let results = CoreDataStack.shared.fetchEntities(
                ofType: GlucoseStored.self,
                onContext: context,
                predicate: NSPredicate.predicateForSixHoursAgo,
                key: "date",
                ascending: false,
                fetchLimit: 72,
                batchSize: 24
            )

            // convert to json
            glucoseAsJSON = self.jsonConverter.convertToJSON(results)
        }

        return glucoseAsJSON ?? "{}"
    }

    private func fetchAndProcessCarbs() -> String {
        // perform fetch AND conversion on the same thread
        // if we do it like this we do not change the thread and do not have to pass the objectIDs
        var carbsAsJSON: String?

        context.performAndWait {
            let results = CoreDataStack.shared.fetchEntities(
                ofType: CarbEntryStored.self,
                onContext: context,
                predicate: NSPredicate.predicateForOneDayAgo,
                key: "date",
                ascending: false
            )

            // convert to json
            carbsAsJSON = self.jsonConverter.convertToJSON(results)
        }

        return carbsAsJSON ?? "{}"
    }

    private func fetchPumpHistoryObjectIDs() -> [NSManagedObjectID]? {
        context.performAndWait {
            let results = CoreDataStack.shared.fetchEntities(
                ofType: PumpEventStored.self,
                onContext: context,
                predicate: NSPredicate.pumpHistoryLast24h,
                key: "timestamp",
                ascending: false,
                batchSize: 50
            )
            return results.map(\.objectID)
        }
    }

    private func parsePumpHistory(_ pumpHistoryObjectIDs: [NSManagedObjectID]) -> String {
        // Return an empty JSON object if the list of object IDs is empty
        guard !pumpHistoryObjectIDs.isEmpty else { return "{}" }

        // Execute all operations on the background context
        let jsonResult = context.performAndWait {
            // Load the pump events from the object IDs
            let pumpHistory: [PumpEventStored] = pumpHistoryObjectIDs
                .compactMap { context.object(with: $0) as? PumpEventStored }

            // Create the DTOs
            let dtos: [PumpEventDTO] = pumpHistory.flatMap { event -> [PumpEventDTO] in
                var eventDTOs: [PumpEventDTO] = []
                if let bolusDTO = event.toBolusDTOEnum() {
                    eventDTOs.append(bolusDTO)
                }
                if let tempBasalDTO = event.toTempBasalDTOEnum() {
                    eventDTOs.append(tempBasalDTO)
                }
                if let tempBasalDurationDTO = event.toTempBasalDurationDTOEnum() {
                    eventDTOs.append(tempBasalDurationDTO)
                }
                return eventDTOs
            }

            // Convert the DTOs to JSON
            return jsonConverter.convertToJSON(dtos)
        }

        // Return the JSON result
        return jsonResult
    }

    func determineBasal(currentTemp: TempBasal, clock: Date = Date()) -> Future<Determination?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start determineBasal")
                // clock
                self.storage.save(clock, as: Monitor.clock)
                let pass = self.loadFileFromStorage(name: Monitor.clock)

                // temp_basal
                let tempBasal = currentTemp.rawJSON
                self.storage.save(tempBasal, as: Monitor.tempBasal)

                let pumpHistoryObjectIDs = self.fetchPumpHistoryObjectIDs() ?? []
                let pumpHistoryJSON = self.parsePumpHistory(pumpHistoryObjectIDs)

                // carbs
                let carbsAsJSON = self.fetchAndProcessCarbs()

                /// glucose
                let glucoseAsJSON = self.fetchAndProcessGlucose()

                /// profile
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)

                /// meal
                let meal = self.meal(
                    pumphistory: pumpHistoryJSON,
                    profile: profile,
                    basalProfile: basalProfile,
                    clock: pass,
                    carbs: carbsAsJSON,
                    glucose: glucoseAsJSON
                )
                self.storage.save(meal, as: Monitor.meal)

                // iob
                let autosens = self.loadFileFromStorage(name: Settings.autosense)
                let iob = self.iob(
                    pumphistory: pumpHistoryJSON,
                    profile: profile,
                    clock: pass,
                    autosens: autosens.isEmpty ? .null : autosens
                )

                self.storage.save(iob, as: Monitor.iob)

                // determine-basal
                let reservoir = self.loadFileFromStorage(name: Monitor.reservoir)

                let preferences = self.loadFileFromStorage(name: Settings.preferences)

                // oref2
                let oref2_variables = self.oref2()

                let orefDetermination = self.determineBasal(
                    glucose: glucoseAsJSON,
                    currentTemp: tempBasal,
                    iob: iob,
                    profile: profile,
                    autosens: autosens.isEmpty ? .null : autosens,
                    meal: meal,
                    microBolusAllowed: true,
                    reservoir: reservoir,
                    pumpHistory: pumpHistoryJSON,
                    preferences: preferences,
                    basalProfile: basalProfile,
                    oref2_variables: oref2_variables
                )
                debug(.openAPS, "Determinated: \(orefDetermination)")

                if var determination = Determination(from: orefDetermination) {
                    determination.timestamp = determination.deliverAt ?? clock
                    self.storage.save(determination, as: Enact.suggested)

                    // save to core data asynchronously
                    self.processDetermination(determination)

                    if determination.tdd ?? 0 > 0 {
                        self.context.perform {
                            let saveToTDD = TDD(context: self.context)

                            saveToTDD.timestamp = determination.timestamp ?? Date()
                            saveToTDD.tdd = (determination.tdd ?? 0) as NSDecimalNumber?
                            do {
                                guard self.context.hasChanges else { return }
                                try self.context.save()
                            } catch {
                                print(error.localizedDescription)
                            }

                            let saveTarget = Target(context: self.context)
                            saveTarget.current = (determination.current_target ?? 100) as NSDecimalNumber?
                            do {
                                guard self.context.hasChanges else { return }
                                try self.context.save()
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                    }

                    promise(.success(determination))
                } else {
                    promise(.success(nil))
                }
            }
        }
    }

    func oref2() -> RawJSON {
        context.performAndWait {
            let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
            let wp = preferences?.weightPercentage ?? 1
            let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30) as NSDecimalNumber
            let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30) as NSDecimalNumber

            let tenDaysAgo = Date().addingTimeInterval(-10.days.timeInterval)
            let twoHoursAgo = Date().addingTimeInterval(-2.hours.timeInterval)

            var uniqueEvents = [TDD]()
            let requestTDD = TDD.fetchRequest() as NSFetchRequest<TDD>
            requestTDD.predicate = NSPredicate(format: "timestamp > %@ AND tdd > 0", tenDaysAgo as NSDate)
            let sortTDD = NSSortDescriptor(key: "timestamp", ascending: true)
            requestTDD.sortDescriptors = [sortTDD]
            try? uniqueEvents = context.fetch(requestTDD)

            var sliderArray = [TempTargetsSlider]()
            let requestIsEnbled = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
            requestIsEnbled.sortDescriptors = [sortIsEnabled]
            // requestIsEnbled.fetchLimit = 1
            try? sliderArray = context.fetch(requestIsEnbled)

            var overrideArray = [Override]()
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            // requestOverrides.fetchLimit = 1
            try? overrideArray = context.fetch(requestOverrides)

            var tempTargetsArray = [TempTargets]()
            let requestTempTargets = TempTargets.fetchRequest() as NSFetchRequest<TempTargets>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            requestTempTargets.fetchLimit = 1
            try? tempTargetsArray = context.fetch(requestTempTargets)

            let total = uniqueEvents.compactMap({ each in each.tdd as? Decimal ?? 0 }).reduce(0, +)
            var indeces = uniqueEvents.count
            // Only fetch once. Use same (previous) fetch
            let twoHoursArray = uniqueEvents.filter({ ($0.timestamp ?? Date()) >= twoHoursAgo })
            var nrOfIndeces = twoHoursArray.count
            let totalAmount = twoHoursArray.compactMap({ each in each.tdd as? Decimal ?? 0 }).reduce(0, +)

            var temptargetActive = tempTargetsArray.first?.active ?? false
            let isPercentageEnabled = sliderArray.first?.enabled ?? false

            var useOverride = overrideArray.first?.enabled ?? false
            var overridePercentage = Decimal(overrideArray.first?.percentage ?? 100)
            var unlimited = overrideArray.first?.indefinite ?? true
            var disableSMBs = overrideArray.first?.smbIsOff ?? false

            let currentTDD = (uniqueEvents.last?.tdd ?? 0) as Decimal

            if indeces == 0 {
                indeces = 1
            }
            if nrOfIndeces == 0 {
                nrOfIndeces = 1
            }

            let average2hours = totalAmount / Decimal(nrOfIndeces)
            let average14 = total / Decimal(indeces)

            let weight = wp
            let weighted_average = weight * average2hours + (1 - weight) * average14

            var duration: Decimal = 0
            var newDuration: Decimal = 0
            var overrideTarget: Decimal = 0

            if useOverride {
                duration = (overrideArray.first?.duration ?? 0) as Decimal
                overrideTarget = (overrideArray.first?.target ?? 0) as Decimal
                let advancedSettings = overrideArray.first?.advancedSettings ?? false
                let addedMinutes = Int(duration)
                let date = overrideArray.first?.date ?? Date()
                if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(),
                   !unlimited
                {
                    useOverride = false
                    let saveToCoreData = Override(context: self.context)
                    saveToCoreData.enabled = false
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = 0
                    saveToCoreData.indefinite = false
                    saveToCoreData.percentage = 100
                    do {
                        guard self.context.hasChanges else { return "{}" }
                        try self.context.save()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }

            if !useOverride {
                unlimited = true
                overridePercentage = 100
                duration = 0
                overrideTarget = 0
                disableSMBs = false
            }

            if temptargetActive {
                var duration_ = 0
                var hbt = Double(hbt_)
                var dd = 0.0

                if temptargetActive {
                    duration_ = Int(truncating: tempTargetsArray.first?.duration ?? 0)
                    hbt = tempTargetsArray.first?.hbt ?? Double(hbt_)
                    let startDate = tempTargetsArray.first?.startDate ?? Date()
                    let durationPlusStart = startDate.addingTimeInterval(duration_.minutes.timeInterval)
                    dd = durationPlusStart.timeIntervalSinceNow.minutes

                    if dd > 0.1 {
                        hbt_ = Decimal(hbt)
                        temptargetActive = true
                    } else {
                        temptargetActive = false
                    }
                }
            }

            if currentTDD > 0 {
                let averages = Oref2_variables(
                    average_total_data: average14,
                    weightedAverage: weighted_average,
                    past2hoursAverage: average2hours,
                    date: Date(),
                    isEnabled: temptargetActive,
                    presetActive: isPercentageEnabled,
                    overridePercentage: overridePercentage,
                    useOverride: useOverride,
                    duration: duration,
                    unlimited: unlimited,
                    hbt: hbt_,
                    overrideTarget: overrideTarget,
                    smbIsOff: disableSMBs,
                    advancedSettings: overrideArray.first?.advancedSettings ?? false,
                    isfAndCr: overrideArray.first?.isfAndCr ?? false,
                    isf: overrideArray.first?.isf ?? false,
                    cr: overrideArray.first?.cr ?? false,
                    smbIsAlwaysOff: overrideArray.first?.smbIsAlwaysOff ?? false,
                    start: (overrideArray.first?.start ?? 0) as Decimal,
                    end: (overrideArray.first?.end ?? 0) as Decimal,
                    smbMinutes: (overrideArray.first?.smbMinutes ?? smbMinutes) as Decimal,
                    uamMinutes: (overrideArray.first?.uamMinutes ?? uamMinutes) as Decimal
                )
                storage.save(averages, as: OpenAPS.Monitor.oref2_variables)
                return self.loadFileFromStorage(name: Monitor.oref2_variables)

            } else {
                let averages = Oref2_variables(
                    average_total_data: 0,
                    weightedAverage: 1,
                    past2hoursAverage: 0,
                    date: Date(),
                    isEnabled: temptargetActive,
                    presetActive: isPercentageEnabled,
                    overridePercentage: overridePercentage,
                    useOverride: useOverride,
                    duration: duration,
                    unlimited: unlimited,
                    hbt: hbt_,
                    overrideTarget: overrideTarget,
                    smbIsOff: disableSMBs,
                    advancedSettings: overrideArray.first?.advancedSettings ?? false,
                    isfAndCr: overrideArray.first?.isfAndCr ?? false,
                    isf: overrideArray.first?.isf ?? false,
                    cr: overrideArray.first?.cr ?? false,
                    smbIsAlwaysOff: overrideArray.first?.smbIsAlwaysOff ?? false,
                    start: (overrideArray.first?.start ?? 0) as Decimal,
                    end: (overrideArray.first?.end ?? 0) as Decimal,
                    smbMinutes: (overrideArray.first?.smbMinutes ?? smbMinutes) as Decimal,
                    uamMinutes: (overrideArray.first?.uamMinutes ?? uamMinutes) as Decimal
                )
                storage.save(averages, as: OpenAPS.Monitor.oref2_variables)
                return self.loadFileFromStorage(name: Monitor.oref2_variables)
            }
        }
    }

    func autosense() -> Future<Autosens?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autosens")

                // pump history
                let pumpHistoryObjectIDs = self.fetchPumpHistoryObjectIDs() ?? []
                let pumpHistoryJSON = self.parsePumpHistory(pumpHistoryObjectIDs)

                // carbs
                let carbsAsJSON = self.fetchAndProcessCarbs()

                /// glucose
                let glucoseAsJSON = self.fetchAndProcessGlucose()

                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let autosensResult = self.autosense(
                    glucose: glucoseAsJSON,
                    pumpHistory: pumpHistoryJSON,
                    basalprofile: basalProfile,
                    profile: profile,
                    carbs: carbsAsJSON,
                    temptargets: tempTargets
                )

                debug(.openAPS, "AUTOSENS: \(autosensResult)")
                if var autosens = Autosens(from: autosensResult) {
                    autosens.timestamp = Date()
                    self.storage.save(autosens, as: Settings.autosense)
                    promise(.success(autosens))
                } else {
                    promise(.success(nil))
                }
            }
        }
    }

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) -> Future<Autotune?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autotune")

                // pump history
                let pumpHistoryObjectIDs = self.fetchPumpHistoryObjectIDs() ?? []
                let pumpHistoryJSON = self.parsePumpHistory(pumpHistoryObjectIDs)

                /// glucose
                let glucoseAsJSON = self.fetchAndProcessGlucose()

                let profile = self.loadFileFromStorage(name: Settings.profile)
                let pumpProfile = self.loadFileFromStorage(name: Settings.pumpProfile)

                // carbs
                let carbsAsJSON = self.fetchAndProcessCarbs()

                let autotunePreppedGlucose = self.autotunePrepare(
                    pumphistory: pumpHistoryJSON,
                    profile: profile,
                    glucose: glucoseAsJSON,
                    pumpprofile: pumpProfile,
                    carbs: carbsAsJSON,
                    categorizeUamAsBasal: categorizeUamAsBasal,
                    tuneInsulinCurve: tuneInsulinCurve
                )
                debug(.openAPS, "AUTOTUNE PREP: \(autotunePreppedGlucose)")

                let previousAutotune = self.storage.retrieve(Settings.autotune, as: RawJSON.self)

                let autotuneResult = self.autotuneRun(
                    autotunePreparedData: autotunePreppedGlucose,
                    previousAutotuneResult: previousAutotune ?? profile,
                    pumpProfile: pumpProfile
                )

                debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult)")

                if let autotune = Autotune(from: autotuneResult) {
                    self.storage.save(autotuneResult, as: Settings.autotune)
                    promise(.success(autotune))
                } else {
                    promise(.success(nil))
                }
            }
        }
    }

    func makeProfiles(useAutotune: Bool) -> Future<Autotune?, Never> {
        Future { promise in
            debug(.openAPS, "Start makeProfiles")
            self.processQueue.async {
                var preferences = self.loadFileFromStorage(name: Settings.preferences)
                if preferences.isEmpty {
                    preferences = Preferences().rawJSON
                }
                let pumpSettings = self.loadFileFromStorage(name: Settings.settings)
                let bgTargets = self.loadFileFromStorage(name: Settings.bgTargets)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let isf = self.loadFileFromStorage(name: Settings.insulinSensitivities)
                let cr = self.loadFileFromStorage(name: Settings.carbRatios)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let model = self.loadFileFromStorage(name: Settings.model)
                let autotune = useAutotune ? self.loadFileFromStorage(name: Settings.autotune) : .empty
                let freeaps = self.loadFileFromStorage(name: FreeAPS.settings)

                let pumpProfile = self.makeProfile(
                    preferences: preferences,
                    pumpSettings: pumpSettings,
                    bgTargets: bgTargets,
                    basalProfile: basalProfile,
                    isf: isf,
                    carbRatio: cr,
                    tempTargets: tempTargets,
                    model: model,
                    autotune: RawJSON.null,
                    freeaps: freeaps
                )

                let profile = self.makeProfile(
                    preferences: preferences,
                    pumpSettings: pumpSettings,
                    bgTargets: bgTargets,
                    basalProfile: basalProfile,
                    isf: isf,
                    carbRatio: cr,
                    tempTargets: tempTargets,
                    model: model,
                    autotune: autotune.isEmpty ? .null : autotune,
                    freeaps: freeaps
                )

                self.storage.save(pumpProfile, as: Settings.pumpProfile)
                self.storage.save(profile, as: Settings.profile)

                if let tunedProfile = Autotune(from: profile) {
                    promise(.success(tunedProfile))
                    return
                }

                promise(.success(nil))
            }
        }
    }

    // MARK: - Private

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.iob))
            worker.evaluate(script: Script(name: Prepare.iob))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                autosens
            ])
        }
    }

    private func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.meal))
            worker.evaluate(script: Script(name: Prepare.meal))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                glucose,
                basalProfile,
                carbs
            ])
        }
    }

    private func autotunePrepare(
        pumphistory: JSON,
        profile: JSON,
        glucose: JSON,
        pumpprofile: JSON,
        carbs: JSON,
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autotunePrep))
            worker.evaluate(script: Script(name: Prepare.autotunePrep))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                glucose,
                pumpprofile,
                carbs,
                categorizeUamAsBasal,
                tuneInsulinCurve
            ])
        }
    }

    private func autotuneRun(
        autotunePreparedData: JSON,
        previousAutotuneResult: JSON,
        pumpProfile: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autotuneCore))
            worker.evaluate(script: Script(name: Prepare.autotuneCore))
            return worker.call(function: Function.generate, with: [
                autotunePreparedData,
                previousAutotuneResult,
                pumpProfile
            ])
        }
    }

    private func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        pumpHistory: JSON,
        preferences: JSON,
        basalProfile: JSON,
        oref2_variables: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Prepare.determineBasal))
            worker.evaluate(script: Script(name: Bundle.basalSetTemp))
            worker.evaluate(script: Script(name: Bundle.getLastGlucose))
            worker.evaluate(script: Script(name: Bundle.determineBasal))

            if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
                worker.evaluate(script: middleware)
            }

            return worker.call(
                function: Function.generate,
                with: [
                    iob,
                    currentTemp,
                    glucose,
                    profile,
                    autosens,
                    meal,
                    microBolusAllowed,
                    reservoir,
                    Date(),
                    pumpHistory,
                    preferences,
                    basalProfile,
                    oref2_variables
                ]
            )
        }
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autosens))
            worker.evaluate(script: Script(name: Prepare.autosens))
            return worker.call(
                function: Function.generate,
                with: [
                    glucose,
                    pumpHistory,
                    basalprofile,
                    profile,
                    carbs,
                    temptargets
                ]
            )
        }
    }

    private func exportDefaultPreferences() -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))
            return worker.call(function: Function.exportDefaults, with: [])
        }
    }

    private func makeProfile(
        preferences: JSON,
        pumpSettings: JSON,
        bgTargets: JSON,
        basalProfile: JSON,
        isf: JSON,
        carbRatio: JSON,
        tempTargets: JSON,
        model: JSON,
        autotune: JSON,
        freeaps: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))
            return worker.call(
                function: Function.generate,
                with: [
                    pumpSettings,
                    bgTargets,
                    isf,
                    basalProfile,
                    preferences,
                    carbRatio,
                    tempTargets,
                    model,
                    autotune,
                    freeaps
                ]
            )
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    private func middlewareScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: "Middleware", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "Middleware", body: try! String(contentsOf: url))
        }

        return nil
    }

    static func defaults(for file: String) -> RawJSON {
        let prefix = file.hasSuffix(".json") ? "json/defaults" : "javascript"
        guard let url = Foundation.Bundle.main.url(forResource: "\(prefix)/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }

    func processAndSave(forecastData: [String: [Int]]) {
        let currentDate = Date()

        context.perform {
            for (type, values) in forecastData {
                self.createForecast(type: type, values: values, date: currentDate, context: self.context)
            }

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    func createForecast(type: String, values: [Int], date: Date, context: NSManagedObjectContext) {
        let forecast = Forecast(context: context)
        forecast.id = UUID()
        forecast.date = date
        forecast.type = type

        for (index, value) in values.enumerated() {
            let forecastValue = ForecastValue(context: context)
            forecastValue.value = Int32(value)
            forecastValue.index = Int32(index)
            forecastValue.forecast = forecast
        }
    }
}
