import CoreData
import Foundation
import Swinject

protocol BolusCalculationManager {
    func calculateInsulin(input: CalculationInput) async -> CalculationResult
    func handleBolusCalculation(
        carbs: Decimal,
        useFattyMealCorrection: Bool,
        useSuperBolus: Bool,
        lastLoopDate: Date,
        minPredBG: Decimal?,
        simulatedCOB: Int16?,
        isBackdated: Bool
    ) async -> CalculationResult
}

final class BaseBolusCalculationManager: BolusCalculationManager, Injectable {
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var fileStorage: FileStorage!
    @Injected() private var determinationStorage: DeterminationStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    // MARK: - Types

    private struct GlucoseVariables {
        var currentBG: Decimal
        var deltaBG: Decimal
    }

    private struct BolusCalculatorVariables {
        var insulinRequired: Decimal
        var evBG: Decimal
        var minPredBG: Decimal
        var lastLoopDate: Date?
        var target: Decimal
        var isf: Decimal
        var cob: Int16
        var iob: Decimal
        var basal: Decimal
        var carbRatio: Decimal
        var insulinCalculated: Decimal
    }

    private enum SettingType {
        case basal
        case carbRatio
        case bgTarget
        case isf
    }

    /// Retrieves current settings from the SettingsManager
    /// - Returns: Tuple containing units, fraction, fattyMealFactor, sweetMealFactor, and maxCarbs settings
    private func getSettings() async -> (
        units: GlucoseUnits,
        fraction: Decimal,
        fattyMealFactor: Decimal,
        sweetMealFactor: Decimal,
        maxCarbs: Decimal
    ) {
        return (
            units: settingsManager.settings.units,
            fraction: settingsManager.settings.overrideFactor,
            fattyMealFactor: settingsManager.settings.fattyMealFactor,
            sweetMealFactor: settingsManager.settings.sweetMealFactor,
            maxCarbs: settingsManager.settings.maxCarbs
        )
    }

    /// Gets the current setting value for a specific setting type based on the time of day
    /// - Parameter type: The type of setting to retrieve (basal, carbRatio, bgTarget, or isf)
    /// - Returns: The current decimal value for the specified setting type
    private func getCurrentSettingValue(for type: SettingType) async -> Decimal {
        let entries: [(start: String, value: Decimal)]

        switch type {
        case .basal:
            let basalEntries = await getBasalProfile()
            entries = basalEntries.map { ($0.start, $0.rate) }
        case .carbRatio:
            let carbRatios = await getCarbRatios()
            entries = carbRatios.schedule.map { ($0.start, $0.ratio) }
        case .bgTarget:
            let bgTargets = await getBGTargets()
            entries = bgTargets.targets.map { ($0.start, $0.low) }
        case .isf:
            let isfValues = await getISFValues()
            entries = isfValues.sensitivities.map { ($0.start, $0.sensitivity) }
        }
        return BolusCalculator.scheduleValue(entries, at: Date())
    }

    /// Retrieves the pump settings from storage
    /// - Returns: PumpSettings object containing pump configuration
    private func getPumpSettings() async -> PumpSettings {
        await fileStorage.retrieveAsync(OpenAPS.Settings.settings, as: PumpSettings.self)
            ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
            ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
    }

    /// Retrieves the basal profile from storage
    /// - Returns: Array of BasalProfileEntry objects
    private func getBasalProfile() async -> [BasalProfileEntry] {
        await fileStorage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
            ?? []
    }

    /// Retrieves carb ratios from storage
    /// - Returns: CarbRatios object containing carb ratio schedule
    private func getCarbRatios() async -> CarbRatios {
        await fileStorage.retrieveAsync(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
            ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
            ?? CarbRatios(units: .grams, schedule: [])
    }

    /// Retrieves blood glucose targets from storage
    /// - Returns: BGTargets object containing target schedule
    private func getBGTargets() async -> BGTargets {
        await fileStorage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
    }

    /// Retrieves insulin sensitivity factors from storage
    /// - Returns: InsulinSensitivities object containing sensitivity schedule
    private func getISFValues() async -> InsulinSensitivities {
        await fileStorage.retrieveAsync(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
            ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
            ?? InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: []
            )
    }

    /// Retrieves Preferences from storage
    /// - Returns: Preferences object containing maxIOB and maxCOB
    private func getPreferences() async -> Preferences {
        await fileStorage.retrieveAsync(OpenAPS.Settings.preferences, as: Preferences.self)
            ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
            ?? Preferences(maxIOB: 0, maxCOB: 120)
    }

    /// Fetches recent glucose readings from CoreData
    /// - Returns: Array of NSManagedObjectIDs for glucose readings
    private func fetchGlucose() async throws -> [NSManagedObjectID] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchGlucose"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Updates glucose-related variables based on recent readings
    /// - Parameter objects: Array of GlucoseStored objects
    /// - Returns: GlucoseVariables containing current blood glucose and delta
    private func updateGlucoseVariables(with objects: [GlucoseStored]) -> GlucoseVariables {
        let glucose = BolusCalculator.glucoseVariables(
            newestFirst: objects.map { (date: $0.date, glucose: Decimal($0.glucose)) },
            now: Date()
        )
        return GlucoseVariables(currentBG: glucose.currentBG, deltaBG: glucose.deltaBG)
    }

    /// Updates bolus calculator variables based on recent determinations and current settings
    /// - Parameters:
    ///   - objects: Array of OrefDetermination objects
    ///   - currentBGTarget: Current blood glucose target
    ///   - currentISF: Current insulin sensitivity factor
    ///   - currentCarbRatio: Current carb ratio
    ///   - currentBasal: Current basal rate
    /// - Returns: BolusCalculatorVariables containing updated calculation parameters
    private func updateBolusCalculatorVariables(
        with objects: [OrefDetermination],
        currentBGTarget: Decimal,
        currentISF: Decimal,
        currentCarbRatio: Decimal,
        currentBasal: Decimal
    ) -> BolusCalculatorVariables {
        guard let mostRecentDetermination = objects.first else {
            return BolusCalculatorVariables(
                insulinRequired: 0,
                evBG: 0,
                minPredBG: 0,
                lastLoopDate: nil,
                target: currentBGTarget,
                isf: currentISF,
                cob: 0,
                iob: 0,
                basal: currentBasal,
                carbRatio: currentCarbRatio,
                insulinCalculated: 0
            )
        }

        return BolusCalculatorVariables(
            insulinRequired: (mostRecentDetermination.insulinReq ?? 0) as Decimal,
            evBG: (mostRecentDetermination.eventualBG ?? 0) as Decimal,
            minPredBG: (mostRecentDetermination.minPredBGFromReason ?? 0) as Decimal,
            lastLoopDate: apsManager.lastLoopDate as Date?,
            target: (mostRecentDetermination.currentTarget ?? currentBGTarget as NSDecimalNumber) as Decimal,
            isf: (mostRecentDetermination.insulinSensitivity ?? NSDecimalNumber(decimal: currentISF)) as Decimal,
            cob: mostRecentDetermination.cob as Int16,
            iob: (mostRecentDetermination.iob ?? 0) as Decimal,
            basal: currentBasal,
            carbRatio: (mostRecentDetermination.carbRatio ?? NSDecimalNumber(decimal: currentCarbRatio)) as Decimal,
            insulinCalculated: 0
        )
    }

    private func prepareCalculationInput(
        carbs: Decimal,
        useFattyMealCorrection: Bool,
        useSuperBolus: Bool,
        lastLoopDate: Date,
        minPredBG: Decimal?,
        simulatedCOB: Int16?,
        isBackdated: Bool
    ) async throws -> CalculationInput {
        do {
            // Get settings
            let settings = await getSettings()

            // Get max bolus
            let maxBolus = await getPumpSettings().maxBolus

            // Get current profile values
            let currentBasal = await getCurrentSettingValue(for: .basal)
            let currentCarbRatio = await getCurrentSettingValue(for: .carbRatio)
            let currentBGTarget = await getCurrentSettingValue(for: .bgTarget)
            let currentISF = await getCurrentSettingValue(for: .isf)

            // Get max IOB and max COB
            let preferences = await getPreferences()
            let maxIOB = preferences.maxIOB
            let maxCOB = preferences.maxCOB

            // Fetch glucose data
            let glucoseFetchContext = CoreDataStack.shared.newTaskContext()
            glucoseFetchContext.name = "handleBolusCalculation.glucose"
            let glucoseIds = try await fetchGlucose()
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared.getNSManagedObject(
                with: glucoseIds,
                context: glucoseFetchContext
            )
            let glucoseVars = await glucoseFetchContext.perform {
                self.updateGlucoseVariables(with: glucoseObjects)
            }

            // Fetch determination data
            let determinationFetchContext = CoreDataStack.shared.newTaskContext()
            determinationFetchContext.name = "handleBolusCalculation.determination"
            let determinationIds = try await determinationStorage.fetchLastDeterminationObjectID(
                predicate: NSPredicate.predicateFor30MinAgoForDetermination
            )
            let determinationObjects: [OrefDetermination] = try await CoreDataStack.shared.getNSManagedObject(
                with: determinationIds,
                context: determinationFetchContext
            )
            let bolusVars = await determinationFetchContext.perform {
                self.updateBolusCalculatorVariables(
                    with: determinationObjects,
                    currentBGTarget: currentBGTarget,
                    currentISF: currentISF,
                    currentCarbRatio: currentCarbRatio,
                    currentBasal: currentBasal
                )
            }

            // If the entry is backdated (user explicitly changed the date), set carbs to 0
            // This prevents double-counting of carbs (entered carbs + COB from backdated entry)
            let effectiveCarbs = isBackdated ? 0 : carbs
            let effectiveCob = isBackdated ? simulatedCOB : bolusVars.cob

            return CalculationInput(
                carbs: effectiveCarbs,
                currentBG: glucoseVars.currentBG,
                deltaBG: glucoseVars.deltaBG,
                target: bolusVars.target,
                isf: bolusVars.isf,
                carbRatio: bolusVars.carbRatio,
                iob: bolusVars.iob,
                cob: effectiveCob ?? bolusVars.cob,
                useFattyMealCorrectionFactor: useFattyMealCorrection,
                fattyMealFactor: settings.fattyMealFactor,
                useSuperBolus: useSuperBolus,
                sweetMealFactor: settings.sweetMealFactor,
                basal: bolusVars.basal,
                fraction: settings.fraction,
                maxBolus: maxBolus,
                maxIOB: maxIOB,
                maxCOB: maxCOB,
                minPredBG: minPredBG ?? bolusVars.minPredBG,
                lastLoopDate: lastLoopDate
            )
        } catch {
            // Return default values in case of error
            throw error
        }
    }

    /// Calculates the recommended insulin dose based on various parameters
    /// - Parameter input: CalculationInput containing all necessary parameters
    /// - Returns: CalculationResult with detailed breakdown of the calculation
    func calculateInsulin(input: CalculationInput) async -> CalculationResult {
        BolusCalculator.calculate(input) { self.apsManager.roundBolus(amount: $0) }
    }

    /// Handles the complete bolus calculation process
    /// - Parameters:
    ///   - carbs: Amount of carbohydrates to be consumed
    ///   - useFattyMealCorrection: Whether to apply reduced bolus correction
    ///   - useSuperBolus: Whether to use super bolus calculation
    ///   - minPredBG: Minimum Predicted Glucose determined by Oref
    ///   - simulatedCOB: Optional simulated COB from backdated entries (if available)
    /// - Returns: CalculationResult containing the calculated insulin dose and details
    func handleBolusCalculation(
        carbs: Decimal,
        useFattyMealCorrection: Bool,
        useSuperBolus: Bool,
        lastLoopDate: Date,
        minPredBG: Decimal? = nil,
        simulatedCOB: Int16? = nil,
        isBackdated: Bool = false
    ) async -> CalculationResult {
        do {
            let input = try await prepareCalculationInput(
                carbs: carbs,
                useFattyMealCorrection: useFattyMealCorrection,
                useSuperBolus: useSuperBolus,
                lastLoopDate: lastLoopDate,
                minPredBG: minPredBG,
                simulatedCOB: simulatedCOB,
                isBackdated: isBackdated
            )
            let result = await calculateInsulin(input: input)
            return result
        } catch let calculationError {
            error(.bolus, "Bolus calculation failed, recommending 0 U", error: calculationError)
            // Return safe default values
            return CalculationResult(
                insulinCalculated: 0,
                factoredInsulin: 0,
                wholeCalc: 0,
                iobInsulinReduction: 0,
                superBolusInsulin: 0,
                targetDifference: 0,
                targetDifferenceInsulin: 0,
                fifteenMinutesInsulin: 0,
                wholeCob: 0,
                wholeCobInsulin: 0
            )
        }
    }
}
