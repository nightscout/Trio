import Combine
import CoreData
import Foundation

final class OpenAPS {
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage
    private let tddStorage: TDDStorage
    private let glucoseStorage: GlucoseStorage
    private let carbsStorage: CarbsStorage

    let jsonConverter = JSONConverter()

    private func newContext(_ name: String) -> NSManagedObjectContext {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = name
        return context
    }

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
    func processDetermination(_ determination: Determination, on context: NSManagedObjectContext) async {
        await context.perform {
            let newOrefDetermination = OrefDetermination(context: context)
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
                            let forecast = Forecast(context: context)
                            forecast.id = UUID()
                            forecast.type = type
                            forecast.date = Date()
                            forecast.orefDetermination = newOrefDetermination

                            for (index, value) in values.enumerated() {
                                let forecastValue = ForecastValue(context: context)
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
        await attemptToSaveContext(on: context)
    }

    func attemptToSaveContext(on context: NSManagedObjectContext) async {
        await context.perform {
            do {
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                warning(.storage, "Saving the determination failed", error: error)
            }
        }
    }

    private func fetchPumpHistoryObjectIDs(on context: NSManagedObjectContext) async throws -> [NSManagedObjectID]? {
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
        on context: NSManagedObjectContext,
        _ pumpHistoryObjectIDs: [NSManagedObjectID],
        simulatedBolusAmount: Decimal? = nil
    ) async throws -> [PumpHistoryEvent] {
        // Empty history returns an empty array, which also drops any simulated bolus.
        guard !pumpHistoryObjectIDs.isEmpty else { return [] }

        // Addresses https://github.com/nightscout/Trio/issues/898
        //
        // On a cold start (new user, fresh onboarding, or pump disconnected > 24h),
        // the oldest event in pump history can be a resume with no preceding pump
        // activity. oref interprets this as the end of a suspend that never started,
        // which drives negative IOB and can cause excessive insulin delivery.
        let orphanedResumes = try await fetchOrphanedResumes(on: context)

        // Execute all operations on the background context
        return await context.perform {
            // Load and map pump events to native algorithm models
            var events = OpenAPS.nativePumpHistory(
                pumpHistoryObjectIDs,
                orphanedResumes: orphanedResumes,
                from: context
            )

            // Optionally add the simulated bolus for the bolus-preview simulation
            if let simulatedBolusAmount = simulatedBolusAmount {
                events.insert(self.createSimulatedBolusEvent(simulatedBolusAmount: simulatedBolusAmount), at: 0)
            }

            return events
        }
    }

    /// Fetches and maps pump events into `[PumpHistoryEvent]`, expose this as static and not private for testing
    static func nativePumpHistory(
        _ pumpHistoryObjectIDs: [NSManagedObjectID],
        orphanedResumes: [NSManagedObjectID],
        from context: NSManagedObjectContext
    ) -> [PumpHistoryEvent] {
        let orphanedSet = Set(orphanedResumes)
        let filteredObjectIds = pumpHistoryObjectIDs.filter { !orphanedSet.contains($0) }
        let pumpHistory: [PumpEventStored] = filteredObjectIds
            .compactMap { context.object(with: $0) as? PumpEventStored }

        return pumpHistory.flatMap { $0.toPumpHistoryEvents() }
    }

    private func createSimulatedBolusEvent(simulatedBolusAmount: Decimal) -> PumpHistoryEvent {
        // for the timestamp, subtract 1 second from now to ensure
        // that the algorithm take this simulated bolus into account
        PumpHistoryEvent(
            id: UUID().uuidString,
            type: .bolus,
            timestamp: Date().addingTimeInterval(-1),
            amount: simulatedBolusAmount,
            duration: 0,
            isSMB: true,
            isExternal: false
        )
    }

    /// Detects a cold-start orphaned resume: returns the resume's object ID if it's an orphaned resume
    private func fetchOrphanedResumes(on context: NSManagedObjectContext) async throws -> [NSManagedObjectID] {
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
        for dosingMode: DosingMode,
        currentTemp: TempBasal,
        supportedBasalRates: [Decimal],
        shouldSmoothGlucose: Bool,
        clock: Date = Date(),
        simulatedCarbsAmount: Decimal? = nil,
        simulatedBolusAmount: Decimal? = nil,
        simulatedCarbsDate: Date? = nil,
        simulation: Bool = false
    ) async throws -> Determination? {
        let context = newContext("determineBasal")

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs(on: context) ?? []
        async let carbsFetch = carbsStorage.getCarbsForAlgorithm(
            additionalCarbs: simulatedCarbsAmount ?? 0,
            carbsDate: simulatedCarbsDate
        )

        // second, independent read into the algorithm; needs the same clamp as the profile
        let storedPreferences = await storage.retrieveAsync(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
        async let glucoseFetch = glucoseStorage.getGlucoseForAlgorithm(
            shouldSmoothGlucose: shouldSmoothGlucose,
            fetchHours: OrefPipeline.glucoseHours(storedPreferences)
        )

        async let prepareTrioCustomOrefVariables = prepareTrioCustomOrefVariables(on: context)
        async let profileAsync = loadFileFromStorageAsync(name: Settings.profile)
        async let basalAsync = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let autosenseAsync = loadFileFromStorageAsync(name: Settings.autosense)
        async let reservoirAsync = loadFileFromStorageAsync(name: Monitor.reservoir)
        async let hasSufficientTddForDynamic = tddStorage.hasSufficientTDD()

        // Await the results of asynchronous tasks
        let (
            pumpHistory,
            carbs,
            glucose,
            rawTrioCustomOrefVariables,
            rawProfile,
            rawBasalProfile,
            rawAutosens,
            rawReservoir,
            hasSufficientTdd
        ) = await (
            try parsePumpHistory(on: context, await pumpHistoryObjectIDs, simulatedBolusAmount: simulatedBolusAmount),
            try carbsFetch,
            try glucoseFetch,
            try prepareTrioCustomOrefVariables,
            profileAsync,
            basalAsync,
            autosenseAsync,
            reservoirAsync,
            try hasSufficientTddForDynamic
        )

        // Decode the JSON-at-rest inputs into native models at the call boundary.
        let profile = try JSONBridge.profile(from: rawProfile)
        let basalProfile = try JSONBridge.basalProfile(from: rawBasalProfile)
        let autosens = try JSONBridge.autosens(from: rawAutosens.isEmpty ? .null : rawAutosens)
        let reservoir = Decimal(string: rawReservoir) ?? 100
        let trioCustomOrefVariables = try JSONBridge.trioCustomOrefVariables(from: rawTrioCustomOrefVariables)

        let dosing = try OrefPipeline.dose(
            profile: profile,
            basalProfile: basalProfile,
            autosens: autosens,
            glucose: glucose,
            pumpHistory: pumpHistory,
            carbs: carbs,
            currentTemp: currentTemp,
            reservoir: reservoir,
            preferences: storedPreferences,
            dosingMode: dosingMode,
            hasSufficientTDD: hasSufficientTdd,
            supportedBasalRates: supportedBasalRates,
            trioCustomOrefVariables: trioCustomOrefVariables,
            clock: clock,
            currentTime: Date()
        )

        // TODO: refactor this to core data
        if !simulation {
            storage.save(dosing.iob, as: Monitor.iob)
        }

        let orefDetermination = try dosing.determination.get()

        debug(
            .algorithm,
            "Determination\(simulation ? " (simulation)" : ""): BG \(orefDetermination?.bg ?? 0) mg/dL, IOB \(orefDetermination?.iob ?? 0) U, COB \(orefDetermination?.cob ?? 0) g, ISF \(orefDetermination?.isf ?? 0) mg/dL/U, sensitivity ratio \(orefDetermination?.sensitivityRatio ?? 1)"
        )

        if let determination = orefDetermination, let deliverAt = determination.deliverAt {
            if !simulation {
                // TODO: refactor this to core data
                let cobEntries = (determination.cobProjection ?? []).enumerated().map { index, cob in
                    CobEntry(cob: cob, time: deliverAt.addingTimeInterval(Double(index) * 300))
                }
                storage.save(cobEntries, as: Monitor.cob)

                // save to core data asynchronously
                await processDetermination(determination, on: context)
            }

            return determination
        } else {
            warning(.algorithm, "No determination produced")
            throw APSError.apsError(message: "No determination data.")
        }
    }

    func prepareTrioCustomOrefVariables(on context: NSManagedObjectContext) async throws -> RawJSON {
        try await context.perform {
            let userPreferences = self.storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            let now = Date()
            let override = try self.fetchActiveOverrides(on: context).first?.orefOverride(preferences: userPreferences)

            let trioCustomOrefVariablesData = OrefPipeline.customOrefVariables(
                override: override,
                tdd: try self.tddSummary(now: now, on: context),
                preferences: userPreferences,
                now: now
            )

            // Save and return contents of Trio's custom oref variables
            self.storage.save(trioCustomOrefVariablesData, as: OpenAPS.Monitor.trio_custom_oref_variables)
            return self.loadFileFromStorage(name: Monitor.trio_custom_oref_variables)
        }
    }

    func autosense(shouldSmoothGlucose: Bool) async throws -> Autosens? {
        let context = newContext("autosense")

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs(on: context) ?? []
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
        let (pumpHistory, carbs, glucose, rawProfile, rawBasalProfile, rawTempTargets) = await (
            try parsePumpHistory(on: context, await pumpHistoryObjectIDs),
            try carbsFetch,
            try glucoseFetch,
            getProfile,
            getBasalProfile,
            getTempTargets
        )

        // Decode the JSON-at-rest inputs into native models at the call boundary.
        let profile = try JSONBridge.profile(from: rawProfile)
        let basalProfile = try JSONBridge.basalProfile(from: rawBasalProfile)
        let tempTargets = try JSONBridge.tempTargets(from: rawTempTargets)

        // Autosense
        var autosens = try OrefPipeline.autosens(
            glucose: glucose,
            pumpHistory: pumpHistory,
            basalProfile: basalProfile,
            profile: profile,
            carbs: carbs,
            tempTargets: tempTargets,
            clock: Date()
        )

        debug(.algorithm, "Autosens ratio \(autosens.ratio)")
        autosens.timestamp = Date()
        await storage.saveAsync(autosens, as: Settings.autosense)

        return autosens
    }

    func createProfiles(for dosingMode: DosingMode) async throws {
        let context = newContext("createProfiles")

        // Load required settings and profiles asynchronously
        async let getPumpSettings = loadFileFromStorageAsync(name: Settings.settings)
        async let getBGTargets = loadFileFromStorageAsync(name: Settings.bgTargets)
        async let getBasalProfile = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let getInsulinSensitivities = loadFileFromStorageAsync(name: Settings.insulinSensitivities)
        async let getCarbRatios = loadFileFromStorageAsync(name: Settings.carbRatios)
        async let getTempTargets = loadFileFromStorageAsync(name: Settings.tempTargets)

        let (pumpSettings, bgTargets, basalProfile, insulinSensitivities, carbRatios, tempTargets) = await (
            getPumpSettings,
            getBGTargets,
            getBasalProfile,
            getInsulinSensitivities,
            getCarbRatios,
            getTempTargets
        )

        // Retrieve user preferences, or set defaults if not available
        let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()

        let activeTempTarget: (target: Decimal, halfBasalTarget: Decimal?)? = try await context.perform {
            guard let tempTarget = try self.fetchActiveTempTargets(on: context).first, tempTarget.enabled,
                  let target = tempTarget.target?.decimalValue else { return nil }
            return (target, tempTarget.halfBasalTarget?.decimalValue)
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

            let profile = try OrefPipeline.profile(
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: insulinSensitivities,
                carbRatios: carbRatios,
                tempTargets: tempTargets,
                preferences: preferences,
                activeTempTarget: activeTempTarget,
                dosingMode: dosingMode,
                clock: clock
            )
            debug(
                .algorithm,
                "Profile preferences: HBT=\(profile.halfBasalExerciseTarget), lowTTlowersSens=\(profile.lowTemptargetLowersSensitivity)"
            )

            // The pump profile is the same profile, kept under its own name
            await storage.saveAsync(profile, as: Settings.pumpProfile)
            await storage.saveAsync(profile, as: Settings.profile)
        } catch {
            warning(.algorithm, "Creating profiles failed", error: error)
            throw error
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

    static func defaults(for file: String) -> RawJSON {
        let prefix = file.hasSuffix(".json") ? "json/defaults" : "javascript"
        guard let url = Foundation.Bundle.main.url(forResource: "\(prefix)/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }

    func processAndSave(forecastData: [String: [Int]]) {
        let currentDate = Date()
        let context = newContext("processAndSave")

        context.perform {
            for (type, values) in forecastData {
                self.createForecast(type: type, values: values, date: currentDate, context: context)
            }

            do {
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                warning(.storage, "Saving forecasts failed", error: error)
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
    func fetchActiveTempTargets(on context: NSManagedObjectContext) throws -> [TempTargetStored] {
        try CoreDataStack.shared.fetchEntities(
            ofType: TempTargetStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveTempTarget,
            key: "date",
            ascending: false,
            fetchLimit: 1
        ) as? [TempTargetStored] ?? []
    }

    func fetchActiveOverrides(on context: NSManagedObjectContext) throws -> [OverrideStored] {
        try CoreDataStack.shared.fetchEntities(
            ofType: OverrideStored.self,
            onContext: context,
            predicate: NSPredicate.lastActiveOverride,
            key: "date",
            ascending: false,
            fetchLimit: 1
        ) as? [OverrideStored] ?? []
    }

    /// TDD over the last ten days, as the algorithm reads it.
    func tddSummary(now: Date, on context: NSManagedObjectContext) throws -> OrefPipeline.TDDSummary {
        let rows = try CoreDataStack.shared.fetchEntities(
            ofType: TDDStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date > %@ AND total > 0", now.addingTimeInterval(-10.days.timeInterval) as NSDate),
            key: "date",
            ascending: true,
            propertiesToFetch: ["date", "total"]
        ) as? [[String: Any]] ?? []
        let entries = rows.compactMap { row in
            (row["total"] as? NSDecimalNumber).map { (date: row["date"] as? Date ?? now, total: $0.decimalValue) }
        }
        return OrefPipeline.tddSummary(entries, now: now)
    }
}

extension OverrideStored {
    /// The override as the algorithm reads it; missing SMB/UAM minutes fall back to the preferences.
    func orefOverride(preferences: Preferences?) -> Override {
        Override(
            name: name ?? "",
            enabled: enabled,
            date: date ?? Date(),
            duration: duration?.decimalValue ?? 0,
            indefinite: indefinite,
            percentage: percentage,
            smbIsOff: smbIsOff,
            isPreset: isPreset,
            id: id ?? "",
            overrideTarget: target != nil,
            target: target?.decimalValue ?? 0,
            advancedSettings: advancedSettings,
            isfAndCr: isfAndCr,
            isf: isf,
            cr: cr,
            smbIsScheduledOff: smbIsScheduledOff,
            start: start?.decimalValue ?? 0,
            end: end?.decimalValue ?? 0,
            smbMinutes: smbMinutes?.decimalValue ?? preferences?.maxSMBBasalMinutes ?? 30,
            uamMinutes: uamMinutes?.decimalValue ?? preferences?.maxUAMSMBBasalMinutes ?? 30
        )
    }
}
