import Combine
import CoreData
import Foundation

final class OpenAPS {
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage
    private let tddStorage: TDDStorage
    private let glucoseStorage: GlucoseStorage
    private let carbsStorage: CarbsStorage

    let context = CoreDataStack.shared.newTaskContext()

    let jsonConverter = JSONConverter()

    init(storage: FileStorage, tddStorage: TDDStorage, glucoseStorage: GlucoseStorage, carbsStorage: CarbsStorage) {
        self.storage = storage
        self.tddStorage = tddStorage
        self.glucoseStorage = glucoseStorage
        self.carbsStorage = carbsStorage
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
    ) async throws -> String {
        // Return an empty JSON object if the list of object IDs is empty
        guard !pumpHistoryObjectIDs.isEmpty else { return "{}" }

        // Addresses https://github.com/nightscout/Trio/issues/898
        //
        // On a cold start (new user, fresh onboarding, or pump disconnected > 24h),
        // the oldest event in pump history can be a resume with no preceding pump
        // activity. oref interprets this as the end of a suspend that never started,
        // which drives negative IOB and can cause excessive insulin delivery.
        let orphanedResumes = try await fetchOrphanedResumes()

        // Execute all operations on the background context
        return await context.perform {
            // Load and map pump events to DTOs
            var dtos = self.loadAndMapPumpEvents(pumpHistoryObjectIDs, orphanedResumes: orphanedResumes)

            // Optionally add the IOB as a DTO
            if let simulatedBolusAmount = simulatedBolusAmount {
                let simulatedBolusDTO = self.createSimulatedBolusDTO(simulatedBolusAmount: simulatedBolusAmount)
                dtos.insert(simulatedBolusDTO, at: 0)
            }

            // Convert the DTOs to JSON
            return self.jsonConverter.convertToJSON(dtos)
        }
    }

    private func loadAndMapPumpEvents(
        _ pumpHistoryObjectIDs: [NSManagedObjectID],
        orphanedResumes: [NSManagedObjectID]
    ) -> [PumpEventDTO] {
        OpenAPS.loadAndMapPumpEvents(pumpHistoryObjectIDs, orphanedResumes: orphanedResumes, from: context)
    }

    /// Fetches and parses pump events, expose this as static and not private for testing
    static func loadAndMapPumpEvents(
        _ pumpHistoryObjectIDs: [NSManagedObjectID],
        orphanedResumes: [NSManagedObjectID],
        from context: NSManagedObjectContext
    ) -> [PumpEventDTO] {
        let orphanedSet = Set(orphanedResumes)
        let filteredObjectIds = pumpHistoryObjectIDs.filter { !orphanedSet.contains($0) }
        // Load the pump events from the object IDs
        let pumpHistory: [PumpEventStored] = filteredObjectIds
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

    /// Detects a cold-start orphaned resume: returns the resume's object ID if it's an orphaned resume
    private func fetchOrphanedResumes() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpHistoryLast48h,
            key: "timestamp",
            ascending: true,
            batchSize: 250
        )

        return try await context.perform {
            guard let pumpEventResultsFull = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            let pumpEventResults = pumpEventResultsFull
                .filter { $0.type == EventType.pumpSuspend.rawValue || $0.type == EventType.pumpResume.rawValue }

            // we define an orphaned resume as one without a paired suspend within
            // the most recent 24 hours.
            // **Important**: we pick 48 hours because the standard pump history
            // is 24 hours + 24 hours of inspection for resumes.
            let orphanedResumes = zip(pumpEventResults, pumpEventResults.dropFirst())
                .compactMap { (prev, curr) -> PumpEventStored? in
                    guard let prevTimestamp = prev.timestamp, let currTimestamp = curr.timestamp else {
                        return nil
                    }
                    let interval = currTimestamp.timeIntervalSince(prevTimestamp)

                    // check if the current event is an orphaned resume
                    //  - previous event not a suspend
                    //  - previous event is a suspend but it's more than 24 hours ago
                    if curr.type == EventType.pumpResume.rawValue,
                       prev.type != EventType.pumpSuspend.rawValue || interval > TimeInterval(hours: 24)
                    {
                        return curr
                    }
                    return nil
                }
            // check the first event to see if it's an orphaned resume
            let firstResumeOrphaned = pumpEventResults.first.flatMap({ event -> [PumpEventStored]? in
                guard event.type == EventType.pumpResume.rawValue else { return nil }
                return [event]
            }) ?? []

            return (firstResumeOrphaned + orphanedResumes).map(\.objectID)
        }
    }

    func determineBasal(
        currentTemp: TempBasal,
        shouldSmoothGlucose: Bool,
        clock: Date = Date(),
        simulatedCarbsAmount: Decimal? = nil,
        simulatedBolusAmount: Decimal? = nil,
        simulatedCarbsDate: Date? = nil,
        simulation: Bool = false
    ) async throws -> Determination? {
        debug(.openAPS, "Start determineBasal")

        // temp_basal
        let tempBasal = currentTemp.rawJSON

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs() ?? []
        async let carbsFetch = carbsStorage.getCarbsForAlgorithm(
            additionalCarbs: simulatedCarbsAmount ?? 0,
            carbsDate: simulatedCarbsDate
        )

        var preferences = await storage.retrieveAsync(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
        let glucoseFetchHours = preferences.maxMealAbsorptionTime + 0.5 // MMAT + half hour buffer
        async let glucoseFetch = glucoseStorage.getGlucoseForAlgorithm(
            shouldSmoothGlucose: shouldSmoothGlucose,
            fetchHours: glucoseFetchHours
        )

        async let prepareTrioCustomOrefVariables = prepareTrioCustomOrefVariables()
        async let profileAsync = loadFileFromStorageAsync(name: Settings.profile)
        async let basalAsync = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let autosenseAsync = loadFileFromStorageAsync(name: Settings.autosense)
        async let reservoirAsync = loadFileFromStorageAsync(name: Monitor.reservoir)
        async let hasSufficientTddForDynamic = tddStorage.hasSufficientTDD()

        // Await the results of asynchronous tasks
        let (
            pumpHistoryJSON,
            carbs,
            glucose,
            trioCustomOrefVariables,
            profile,
            basalProfile,
            autosens,
            reservoir,
            hasSufficientTdd
        ) = await (
            try parsePumpHistory(await pumpHistoryObjectIDs, simulatedBolusAmount: simulatedBolusAmount),
            try carbsFetch,
            try glucoseFetch,
            try prepareTrioCustomOrefVariables,
            profileAsync,
            basalAsync,
            autosenseAsync,
            reservoirAsync,
            try hasSufficientTddForDynamic
        )

        // Meal calculation
        let meal = try self.meal(
            pumphistory: pumpHistoryJSON,
            profile: profile,
            basalProfile: basalProfile,
            clock: clock,
            carbs: carbs,
            glucose: glucose
        )

        // IOB calculation
        let iob = try self.iob(
            pumphistory: pumpHistoryJSON,
            profile: profile,
            clock: clock,
            autosens: autosens.isEmpty ? .null : autosens
        )

        // TODO: refactor this to core data
        if !simulation {
            storage.save(iob, as: Monitor.iob)
        }

        if !hasSufficientTdd, preferences.useNewFormula || (preferences.useNewFormula && preferences.sigmoid) {
            debug(.openAPS, "Insufficient TDD for dynamic formula; disabling for determine basal run.")
            preferences.useNewFormula = false
            preferences.sigmoid = false
        }

        // Determine basal
        let orefDetermination = try determineBasal(
            glucose: glucose,
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
            trioCustomOrefVariables: trioCustomOrefVariables
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
            debug(
                .openAPS,
                "\(DebuggingIdentifiers.failed) No determination data. orefDetermination: \(orefDetermination), Determination(from: orefDetermination): \(String(describing: Determination(from: orefDetermination))), deliverAt: \(String(describing: Determination(from: orefDetermination)?.deliverAt))"
            )
            throw APSError.apsError(message: "No determination data.")
        }
    }

    func prepareTrioCustomOrefVariables() async throws -> RawJSON {
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

            let glucose = try self.fetchGlucose()

            // Prepare Trio's custom oref variables
            let trioCustomOrefVariablesData = TrioCustomOrefVariables(
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

            // Save and return contents of Trio's custom oref variables
            self.storage.save(trioCustomOrefVariablesData, as: OpenAPS.Monitor.trio_custom_oref_variables)
            return self.loadFileFromStorage(name: Monitor.trio_custom_oref_variables)
        }
    }

    func autosense(shouldSmoothGlucose: Bool) async throws -> Autosens? {
        debug(.openAPS, "Start autosens")

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs() ?? []
        async let carbsFetch = carbsStorage.getCarbsForAlgorithm(additionalCarbs: nil, carbsDate: nil)
        // Autosens needs the full 24h window for its sensitivity algorithm.
        async let glucoseFetch = glucoseStorage.getGlucoseForAlgorithm(
            shouldSmoothGlucose: shouldSmoothGlucose,
            fetchHours: 24
        )
        async let getProfile = loadFileFromStorageAsync(name: Settings.profile)
        async let getBasalProfile = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let getTempTargets = loadFileFromStorageAsync(name: Settings.tempTargets)

        // Await the results of asynchronous tasks
        let (pumpHistoryJSON, carbs, glucose, profile, basalProfile, tempTargets) = await (
            try parsePumpHistory(await pumpHistoryObjectIDs),
            try carbsFetch,
            try glucoseFetch,
            getProfile,
            getBasalProfile,
            getTempTargets
        )

        // Autosense
        let autosenseResult = try autosense(
            glucose: glucose,
            pumpHistory: pumpHistoryJSON,
            basalprofile: basalProfile,
            profile: profile,
            carbs: carbs,
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
        async let getInsulinSensitivities = loadFileFromStorageAsync(name: Settings.insulinSensitivities)
        async let getCarbRatios = loadFileFromStorageAsync(name: Settings.carbRatios)
        async let getTempTargets = loadFileFromStorageAsync(name: Settings.tempTargets)
        async let getModel = loadFileFromStorageAsync(name: Settings.model)

        let (pumpSettings, bgTargets, basalProfile, insulinSensitivities, carbRatios, tempTargets, model) = await (
            getPumpSettings,
            getBGTargets,
            getBasalProfile,
            getInsulinSensitivities,
            getCarbRatios,
            getTempTargets,
            getModel
        )

        // Retrieve user preferences, or set defaults if not available
        let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
        let defaultHalfBasalTarget = preferences.halfBasalExerciseTarget
        var adjustedPreferences = preferences

        // Check for active Temp Targets and adjust HBT if necessary
        try await context.perform {
            // Check if a Temp Target is active and check HBT differs from setting and adjust
            if let activeTempTarget = try self.fetchActiveTempTargets().first,
               activeTempTarget.enabled,
               let targetValue = activeTempTarget.target?.decimalValue
            {
                // Compute effective HBT - handles both custom HBT and standard TT (where HBT might need adjustment)
                let effectiveHBT = TempTargetCalculations.computeEffectiveHBT(
                    tempTargetHalfBasalTarget: activeTempTarget.halfBasalTarget?.decimalValue,
                    settingHalfBasalTarget: defaultHalfBasalTarget,
                    target: targetValue,
                    autosensMax: preferences.autosensMax
                )

                if let effectiveHBT, effectiveHBT != defaultHalfBasalTarget {
                    adjustedPreferences.halfBasalExerciseTarget = effectiveHBT
                    let percentage = Int(TempTargetCalculations.computeAdjustedPercentage(
                        halfBasalTarget: effectiveHBT,
                        target: targetValue,
                        autosensMax: preferences.autosensMax
                    ))
                    debug(
                        .openAPS,
                        "TempTarget: target=\(targetValue), HBT=\(defaultHalfBasalTarget), effectiveHBT=\(effectiveHBT), percentage=\(percentage)%, adjustmentType=Custom"
                    )
                }
            }
            // Overwrite the lowTTlowersSens if autosensMax does not support it
            if preferences.lowTemptargetLowersSensitivity, preferences.autosensMax <= 1 {
                adjustedPreferences.lowTemptargetLowersSensitivity = false
                debug(.openAPS, "Setting lowTTlowersSens to false due to insufficient autosensMax: \(preferences.autosensMax)")
            }
        }

        let clock = Date()
        do {
            // Decode the raw settings into native models. The bundled-defaults
            // fallback still happens in loadFileFromStorageAsync above, so decoding
            // here preserves the same behavior it previously had inside makeProfile.
            let pumpSettings = try JSONBridge.pumpSettings(from: pumpSettings)
            let bgTargets = try JSONBridge.bgTargets(from: bgTargets)
            let basalProfile = try JSONBridge.basalProfile(from: basalProfile)
            let insulinSensitivities = try JSONBridge.insulinSensitivities(from: insulinSensitivities)
            let carbRatios = try JSONBridge.carbRatios(from: carbRatios)
            let tempTargets = try JSONBridge.tempTargets(from: tempTargets)

            let pumpProfile = try OpenAPSSwift.makeProfile(
                preferences: adjustedPreferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                insulinSensitivities: insulinSensitivities,
                carbRatios: carbRatios,
                tempTargets: tempTargets,
                model: model,
                clock: clock
            )

            let profile = try OpenAPSSwift.makeProfile(
                preferences: adjustedPreferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                insulinSensitivities: insulinSensitivities,
                carbRatios: carbRatios,
                tempTargets: tempTargets,
                model: model,
                clock: clock
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

    private func iob(
        pumphistory: JSON,
        profile: JSON,
        clock: JSON,
        autosens: JSON
    ) throws -> RawJSON {
        // FIXME: For now we'll just remove duplicate suspends here (ISSUE-399)
        var pumphistory = pumphistory
        if let pumpHistoryArray = try? JSONBridge.pumpHistory(from: pumphistory) {
            pumphistory = pumpHistoryArray.removingDuplicateSuspendResumeEvents().rawJSON
        }

        let swiftResult = OpenAPSSwift
            .iob(pumphistory: pumphistory, profile: profile, clock: clock, autosens: autosens)
        return try swiftResult.returnOrThrow()
    }

    private func meal(
        pumphistory: JSON,
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: [CarbsEntry],
        glucose: [BloodGlucose]
    ) throws -> RawJSON {
        let swiftResult = OpenAPSSwift
            .meal(
                pumphistory: pumphistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbs: carbs,
                glucose: glucose
            )
        return try swiftResult.returnOrThrow()
    }

    private func autosense(
        glucose: [BloodGlucose],
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: [CarbsEntry],
        temptargets: JSON
    ) throws -> RawJSON {
        let swiftResult = OpenAPSSwift
            .autosense(
                glucose: glucose,
                pumpHistory: pumpHistory,
                basalProfile: basalprofile,
                profile: profile,
                carbs: carbs,
                tempTargets: temptargets,
                clock: Date()
            )
        return try swiftResult.returnOrThrow()
    }

    private func determineBasal(
        glucose: [BloodGlucose],
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
        trioCustomOrefVariables: JSON
    ) throws -> RawJSON {
        let clock = Date()
        let swiftResult = OpenAPSSwift.determineBasal(
            glucose: glucose,
            currentTemp: currentTemp,
            iob: iob,
            profile: profile,
            autosens: autosens,
            meal: meal,
            microBolusAllowed: microBolusAllowed,
            reservoir: reservoir,
            pumpHistory: pumpHistory,
            preferences: preferences,
            basalProfile: basalProfile,
            trioCustomOrefVariables: trioCustomOrefVariables,
            clock: clock
        )
        return try swiftResult.returnOrThrow()
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

// Non-Async fetch methods for trio_custom_oref_variables
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

    func fetchGlucose() throws -> [GlucoseStored] {
        let results = try CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 4
        )

        return try context.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return glucoseResults
        }
    }
}
