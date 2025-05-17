import Combine
import CoreData
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage
    private let tddStorage: TDDStorage

    let context = CoreDataStack.shared.newTaskContext()

    let jsonConverter = JSONConverter()

    init(storage: FileStorage, tddStorage: TDDStorage) {
        self.storage = storage
        self.tddStorage = tddStorage
    }

    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Helper function to convert a Decimal? to NSDecimalNumber?
    func decimalToNSDecimalNumber(_ value: Decimal?) -> NSDecimalNumber? {
        guard let value = value else { return nil }
        return NSDecimalNumber(decimal: value)
    }

    // Use the helper function for cleaner code
    func processDetermination(_ determination: Determination) async {
        await context.perform {
            let newOrefDetermination = OrefDetermination(context: self.context)
            newOrefDetermination.id = UUID()
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
            newOrefDetermination.duration = self.decimalToNSDecimalNumber(determination.duration)
            newOrefDetermination.iob = self.decimalToNSDecimalNumber(determination.iob)
            newOrefDetermination.threshold = self.decimalToNSDecimalNumber(determination.threshold)
            newOrefDetermination.minDelta = self.decimalToNSDecimalNumber(determination.minDelta)
            newOrefDetermination.sensitivityRatio = self.decimalToNSDecimalNumber(determination.sensitivityRatio)
            newOrefDetermination.expectedDelta = self.decimalToNSDecimalNumber(determination.expectedDelta)
            newOrefDetermination.cob = Int16(Int(determination.cob ?? 0))
            newOrefDetermination.manualBolusErrorString = self.decimalToNSDecimalNumber(determination.manualBolusErrorString)
            newOrefDetermination.smbToDeliver = determination.units.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.carbsRequired = Int16(Int(determination.carbsReq ?? 0))
            newOrefDetermination.isUploadedToNS = false

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
        }

        // First save the current Determination to Core Data
        await attemptToSaveContext()
    }

    func attemptToSaveContext() async {
        await context.perform {
            do {
                guard self.context.hasChanges else { return }
                try self.context.save()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Determination to Core Data")
            }
        }
    }

    // fetch glucose to pass it to the meal function and to determine basal
    private func fetchAndProcessGlucose() async throws -> String {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgoInMinutes,
            key: "date",
            ascending: false,
            fetchLimit: 72,
            batchSize: 24
        )

        return try await context.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            // convert to JSON
            return self.jsonConverter.convertToJSON(glucoseResults)
        }
    }

    private func fetchAndProcessCarbs(additionalCarbs: Decimal? = nil) async throws -> String {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false
        )

        let json = try await context.perform {
            guard let carbResults = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            var jsonArray = self.jsonConverter.convertToJSON(carbResults)

            if let additionalCarbs = additionalCarbs {
                let additionalEntry = [
                    "carbs": Double(additionalCarbs),
                    "actualDate": ISO8601DateFormatter().string(from: Date()),
                    "id": UUID().uuidString,
                    "note": NSNull(),
                    "protein": 0,
                    "created_at": ISO8601DateFormatter().string(from: Date()),
                    "isFPU": false,
                    "fat": 0,
                    "enteredBy": "Trio"
                ] as [String: Any]

                // Assuming jsonArray is a String, convert it to a list of dictionaries first
                if let jsonData = jsonArray.data(using: .utf8) {
                    var jsonList = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]]
                    jsonList?.append(additionalEntry)

                    // Convert back to JSON string
                    if let updatedJsonData = try? JSONSerialization
                        .data(withJSONObject: jsonList ?? [], options: .prettyPrinted)
                    {
                        jsonArray = String(data: updatedJsonData, encoding: .utf8) ?? jsonArray
                    }
                }
            }

            return jsonArray
        }

        return json
    }

    private func fetchPumpHistoryObjectIDs() async throws -> [NSManagedObjectID]? {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpHistoryLast1440Minutes,
            key: "timestamp",
            ascending: false,
            batchSize: 50
        )

        return try await context.perform {
            guard let pumpEventResults = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return pumpEventResults.map(\.objectID)
        }
    }

    private func parsePumpHistory(
        _ pumpHistoryObjectIDs: [NSManagedObjectID],
        simulatedBolusAmount: Decimal? = nil
    ) async -> String {
        // Return an empty JSON object if the list of object IDs is empty
        guard !pumpHistoryObjectIDs.isEmpty else { return "{}" }

        // Execute all operations on the background context
        return await context.perform {
            // Load and map pump events to DTOs
            var dtos = self.loadAndMapPumpEvents(pumpHistoryObjectIDs)

            // Optionally add the IOB as a DTO
            if let simulatedBolusAmount = simulatedBolusAmount {
                let simulatedBolusDTO = self.createSimulatedBolusDTO(simulatedBolusAmount: simulatedBolusAmount)
                dtos.insert(simulatedBolusDTO, at: 0)
            }

            // Convert the DTOs to JSON
            return self.jsonConverter.convertToJSON(dtos)
        }
    }

    private func loadAndMapPumpEvents(_ pumpHistoryObjectIDs: [NSManagedObjectID]) -> [PumpEventDTO] {
        OpenAPS.loadAndMapPumpEvents(pumpHistoryObjectIDs, from: context)
    }

    /// Fetches and parses pump events, expose this as static and not private for testing
    static func loadAndMapPumpEvents(
        _ pumpHistoryObjectIDs: [NSManagedObjectID],
        from context: NSManagedObjectContext
    ) -> [PumpEventDTO] {
        // Load the pump events from the object IDs
        let pumpHistory: [PumpEventStored] = pumpHistoryObjectIDs
            .compactMap { context.object(with: $0) as? PumpEventStored }

        // Create the DTOs
        let dtos: [PumpEventDTO] = pumpHistory.flatMap { event -> [PumpEventDTO] in
            var eventDTOs: [PumpEventDTO] = []
            if let bolusDTO = event.toBolusDTOEnum() {
                eventDTOs.append(bolusDTO)
            }
            if let tempBasalDurationDTO = event.toTempBasalDurationDTOEnum() {
                eventDTOs.append(tempBasalDurationDTO)
            }
            if let tempBasalDTO = event.toTempBasalDTOEnum() {
                eventDTOs.append(tempBasalDTO)
            }
            if let pumpSuspendDTO = event.toPumpSuspendDTO() {
                eventDTOs.append(pumpSuspendDTO)
            }
            if let pumpResumeDTO = event.toPumpResumeDTO() {
                eventDTOs.append(pumpResumeDTO)
            }
            if let rewindDTO = event.toRewindDTO() {
                eventDTOs.append(rewindDTO)
            }
            if let primeDTO = event.toPrimeDTO() {
                eventDTOs.append(primeDTO)
            }
            return eventDTOs
        }
        return dtos
    }

    private func createSimulatedBolusDTO(simulatedBolusAmount: Decimal) -> PumpEventDTO {
        let oneSecondAgo = Calendar.current
            .date(
                byAdding: .second,
                value: -1,
                to: Date()
            )! // adding -1s to the current Date ensures that oref actually uses the mock entry to calculate iob and not guard it away
        let dateFormatted = PumpEventStored.dateFormatter.string(from: oneSecondAgo)

        let bolusDTO = BolusDTO(
            id: UUID().uuidString,
            timestamp: dateFormatted,
            amount: Double(simulatedBolusAmount),
            isExternal: false,
            isSMB: true,
            duration: 0,
            _type: "Bolus"
        )
        return .bolus(bolusDTO)
    }

    func determineBasal(
        currentTemp: TempBasal,
        clock: Date = Date(),
        simulatedCarbsAmount: Decimal? = nil,
        simulatedBolusAmount: Decimal? = nil,
        simulation: Bool = false
    ) async throws -> Determination? {
        debug(.openAPS, "Start determineBasal")

        // temp_basal
        let tempBasal = currentTemp.rawJSON

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs() ?? []
        async let carbs = fetchAndProcessCarbs(additionalCarbs: simulatedCarbsAmount ?? 0)
        async let glucose = fetchAndProcessGlucose()
        async let oref2 = oref2()
        async let profileAsync = loadFileFromStorageAsync(name: Settings.profile)
        async let basalAsync = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let autosenseAsync = loadFileFromStorageAsync(name: Settings.autosense)
        async let reservoirAsync = loadFileFromStorageAsync(name: Monitor.reservoir)
        async let preferencesAsync = storage.retrieveAsync(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
        async let hasSufficientTddForDynamic = tddStorage.hasSufficientTDD()

        // Await the results of asynchronous tasks
        let (
            pumpHistoryJSON,
            carbsAsJSON,
            glucoseAsJSON,
            oref2_variables,
            profile,
            basalProfile,
            autosens,
            reservoir,
            hasSufficientTdd
        ) = await (
            try parsePumpHistory(await pumpHistoryObjectIDs, simulatedBolusAmount: simulatedBolusAmount),
            try carbs,
            try glucose,
            try oref2,
            profileAsync,
            basalAsync,
            autosenseAsync,
            reservoirAsync,
            try hasSufficientTddForDynamic
        )

        // Meal calculation
        let meal = try await self.meal(
            pumphistory: pumpHistoryJSON,
            profile: profile,
            basalProfile: basalProfile,
            clock: clock,
            carbs: carbsAsJSON,
            glucose: glucoseAsJSON
        )

        // IOB calculation
        let iob = try await self.iob(
            pumphistory: pumpHistoryJSON,
            profile: profile,
            clock: clock,
            autosens: autosens.isEmpty ? .null : autosens
        )

        // TODO: refactor this to core data
        if !simulation {
            storage.save(iob, as: Monitor.iob)
        }

        var preferences = await preferencesAsync

        if !hasSufficientTdd, preferences.useNewFormula || (preferences.useNewFormula && preferences.sigmoid) {
            debug(.openAPS, "Insufficient TDD for dynamic formula; disabling for determine basal run.")
            preferences.useNewFormula = false
            preferences.sigmoid = false
        }

        // Determine basal
        let orefDetermination = try await determineBasal(
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

        debug(.openAPS, "\(simulation ? "[SIMULATION]" : "") OREF DETERMINATION: \(orefDetermination)")

        if var determination = Determination(from: orefDetermination), let deliverAt = determination.deliverAt {
            // set both timestamp and deliverAt to the SAME date; this will be updated for timestamp once it is enacted
            // AAPS does it the same way! we'll follow their example!
            determination.timestamp = deliverAt

            if !simulation {
                // save to core data asynchronously
                await processDetermination(determination)
            }

            return determination
        } else {
            throw APSError.apsError(message: "No determination data.")
        }
    }

    func oref2() async throws -> RawJSON {
        try await context.perform {
            // Retrieve user preferences
            let userPreferences = self.storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            let weightPercentage = userPreferences?.weightPercentage ?? 1.0
            let maxSMBBasalMinutes = userPreferences?.maxSMBBasalMinutes ?? 30
            let maxUAMBasalMinutes = userPreferences?.maxUAMSMBBasalMinutes ?? 30

            // Fetch historical events for Total Daily Dose (TDD) calculation
            let tenDaysAgo = Date().addingTimeInterval(-10.days.timeInterval)
            let twoHoursAgo = Date().addingTimeInterval(-2.hours.timeInterval)
            let historicalTDDData = try self.fetchHistoricalTDDData(from: tenDaysAgo)

            // Fetch the last active Override
            let activeOverrides = try self.fetchActiveOverrides()
            let isOverrideActive = activeOverrides.first?.enabled ?? false
            let overridePercentage = Decimal(activeOverrides.first?.percentage ?? 100)
            let isOverrideIndefinite = activeOverrides.first?.indefinite ?? true
            let disableSMBs = activeOverrides.first?.smbIsOff ?? false
            let overrideTargetBG = activeOverrides.first?.target?.decimalValue ?? 0

            // Calculate averages for Total Daily Dose (TDD)
            let totalTDD = historicalTDDData.compactMap { ($0["total"] as? NSDecimalNumber)?.decimalValue }.reduce(0, +)
            let totalDaysCount = max(historicalTDDData.count, 1)

            // Fetch recent TDD data for the past two hours
            let recentTDDData = historicalTDDData.filter { ($0["date"] as? Date ?? Date()) >= twoHoursAgo }
            let recentDataCount = max(recentTDDData.count, 1)
            let recentTotalTDD = recentTDDData.compactMap { ($0["total"] as? NSDecimalNumber)?.decimalValue }
                .reduce(0, +)

            let currentTDD = historicalTDDData.last?["total"] as? Decimal ?? 0
            let averageTDDLastTwoHours = recentTotalTDD / Decimal(recentDataCount)
            let averageTDDLastTenDays = totalTDD / Decimal(totalDaysCount)
            let weightedTDD = weightPercentage * averageTDDLastTwoHours + (1 - weightPercentage) * averageTDDLastTenDays

            // Prepare Oref2 variables
            let oref2Data = Oref2_variables(
                average_total_data: currentTDD > 0 ? averageTDDLastTenDays : 0,
                weightedAverage: currentTDD > 0 ? weightedTDD : 1,
                currentTDD: currentTDD,
                past2hoursAverage: currentTDD > 0 ? averageTDDLastTwoHours : 0,
                date: Date(),
                overridePercentage: overridePercentage,
                useOverride: isOverrideActive,
                duration: activeOverrides.first?.duration?.decimalValue ?? 0,
                unlimited: isOverrideIndefinite,
                overrideTarget: overrideTargetBG,
                smbIsOff: disableSMBs,
                advancedSettings: activeOverrides.first?.advancedSettings ?? false,
                isfAndCr: activeOverrides.first?.isfAndCr ?? false,
                isf: activeOverrides.first?.isf ?? false,
                cr: activeOverrides.first?.cr ?? false,
                smbIsScheduledOff: activeOverrides.first?.smbIsScheduledOff ?? false,
                start: (activeOverrides.first?.start ?? 0) as Decimal,
                end: (activeOverrides.first?.end ?? 0) as Decimal,
                smbMinutes: activeOverrides.first?.smbMinutes?.decimalValue ?? maxSMBBasalMinutes,
                uamMinutes: activeOverrides.first?.uamMinutes?.decimalValue ?? maxUAMBasalMinutes
            )

            // Save and return the Oref2 variables
            self.storage.save(oref2Data, as: OpenAPS.Monitor.oref2_variables)
            return self.loadFileFromStorage(name: Monitor.oref2_variables)
        }
    }

    func autosense() async throws -> Autosens? {
        debug(.openAPS, "Start autosens")

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs() ?? []
        async let carbs = fetchAndProcessCarbs()
        async let glucose = fetchAndProcessGlucose()
        async let getProfile = loadFileFromStorageAsync(name: Settings.profile)
        async let getBasalProfile = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let getTempTargets = loadFileFromStorageAsync(name: Settings.tempTargets)

        // Await the results of asynchronous tasks
        let (pumpHistoryJSON, carbsAsJSON, glucoseAsJSON, profile, basalProfile, tempTargets) = await (
            try parsePumpHistory(await pumpHistoryObjectIDs),
            try carbs,
            try glucose,
            getProfile,
            getBasalProfile,
            getTempTargets
        )

        // Autosense
        let autosenseResult = try await autosense(
            glucose: glucoseAsJSON,
            pumpHistory: pumpHistoryJSON,
            basalprofile: basalProfile,
            profile: profile,
            carbs: carbsAsJSON,
            temptargets: tempTargets
        )

        debug(.openAPS, "AUTOSENS: \(autosenseResult)")
        if var autosens = Autosens(from: autosenseResult) {
            autosens.timestamp = Date()
            await storage.saveAsync(autosens, as: Settings.autosense)

            return autosens
        } else {
            return nil
        }
    }

    func createProfiles() async throws {
        debug(.openAPS, "Start creating pump profile and user profile")

        // Load required settings and profiles asynchronously
        async let getPumpSettings = loadFileFromStorageAsync(name: Settings.settings)
        async let getBGTargets = loadFileFromStorageAsync(name: Settings.bgTargets)
        async let getBasalProfile = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let getISF = loadFileFromStorageAsync(name: Settings.insulinSensitivities)
        async let getCR = loadFileFromStorageAsync(name: Settings.carbRatios)
        async let getTempTargets = loadFileFromStorageAsync(name: Settings.tempTargets)
        async let getModel = loadFileFromStorageAsync(name: Settings.model)
        async let getTrioSettingDefaults = loadFileFromStorageAsync(name: Trio.settings)

        let (pumpSettings, bgTargets, basalProfile, isf, cr, tempTargets, model, trioSettings) = await (
            getPumpSettings,
            getBGTargets,
            getBasalProfile,
            getISF,
            getCR,
            getTempTargets,
            getModel,
            getTrioSettingDefaults
        )

        // Retrieve user preferences, or set defaults if not available
        let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
        let defaultHalfBasalTarget = preferences.halfBasalExerciseTarget
        var adjustedPreferences = preferences

        // Check for active Temp Targets and adjust HBT if necessary
        try await context.perform {
            // Check if a Temp Target is active and if its HBT differs from user preferences
            if let activeTempTarget = try self.fetchActiveTempTargets().first,
               activeTempTarget.enabled,
               let activeHBT = activeTempTarget.halfBasalTarget?.decimalValue,
               activeHBT != defaultHalfBasalTarget
            {
                // Overwrite the HBT in preferences
                adjustedPreferences.halfBasalExerciseTarget = activeHBT
                debug(.openAPS, "Updated halfBasalExerciseTarget to active Temp Target value: \(activeHBT)")
            }
            // Overwrite the lowTTlowersSens if autosensMax does not support it
            if preferences.lowTemptargetLowersSensitivity, preferences.autosensMax <= 1 {
                adjustedPreferences.lowTemptargetLowersSensitivity = false
                debug(.openAPS, "Setting lowTTlowersSens to false due to insufficient autosensMax: \(preferences.autosensMax)")
            }
        }

        do {
            let pumpProfile = try await makeProfile(
                preferences: adjustedPreferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: RawJSON.null,
                trioData: trioSettings
            )

            let profile = try await makeProfile(
                preferences: adjustedPreferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: RawJSON.null,
                trioData: trioSettings
            )

            // Save the profiles
            await storage.saveAsync(pumpProfile, as: Settings.pumpProfile)
            await storage.saveAsync(profile, as: Settings.profile)
        } catch {
            debug(
                .apsManager,
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to create pump profile and normal profile: \(error)"
            )
            throw error
        }
    }

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.iob),
                    Script(name: Prepare.iob)
                ])
                let result = worker.call(function: Function.generate, with: [
                    pumphistory,
                    profile,
                    clock,
                    autosens
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func meal(
        pumphistory: JSON,
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: JSON,
        glucose: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.meal),
                    Script(name: Prepare.meal)
                ])
                let result = worker.call(function: Function.generate, with: [
                    pumphistory,
                    profile,
                    clock,
                    glucose,
                    basalProfile,
                    carbs
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.autosens),
                    Script(name: Prepare.autosens)
                ])
                let result = worker.call(function: Function.generate, with: [
                    glucose,
                    pumpHistory,
                    basalprofile,
                    profile,
                    carbs,
                    temptargets
                ])
                continuation.resume(returning: result)
            }
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
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Prepare.determineBasal),
                    Script(name: Bundle.basalSetTemp),
                    Script(name: Bundle.getLastGlucose),
                    Script(name: Bundle.determineBasal)
                ])

                if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
                    worker.evaluate(script: middleware)
                }

                let result = worker.call(function: Function.generate, with: [
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
                ])

                continuation.resume(returning: result)
            }
        }
    }

    private func exportDefaultPreferences() -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.profile),
                Script(name: Prepare.profile)
            ])
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
        trioData: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.profile),
                    Script(name: Prepare.profile)
                ])
                let result = worker.call(function: Function.generate, with: [
                    pumpSettings,
                    bgTargets,
                    isf,
                    basalProfile,
                    preferences,
                    carbRatio,
                    tempTargets,
                    model,
                    autotune,
                    trioData
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    private func loadFileFromStorageAsync(name: String) async -> RawJSON {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
                continuation.resume(returning: result)
            }
        }
    }

    private func middlewareScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: name, body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            do {
                let body = try String(contentsOf: url)
                return Script(name: name, body: body)
            } catch {
                debug(.openAPS, "Failed to load script \(name): \(error)")
            }
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

// Non-Async fetch methods for oref2
extension OpenAPS {
    func fetchActiveTempTargets() throws -> [TempTargetStored] {
        try CoreDataStack.shared.fetchEntities(
            ofType: TempTargetStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveTempTarget,
            key: "date",
            ascending: false,
            fetchLimit: 1
        ) as? [TempTargetStored] ?? []
    }

    func fetchActiveOverrides() throws -> [OverrideStored] {
        try CoreDataStack.shared.fetchEntities(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveOverride,
            key: "date",
            ascending: false,
            fetchLimit: 1
        ) as? [OverrideStored] ?? []
    }

    func fetchHistoricalTDDData(from date: Date) throws -> [[String: Any]] {
        try CoreDataStack.shared.fetchEntities(
            ofType: TDDStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date > %@ AND total > 0", date as NSDate),
            key: "date",
            ascending: true,
            propertiesToFetch: ["date", "total"]
        ) as? [[String: Any]] ?? []
    }
}
