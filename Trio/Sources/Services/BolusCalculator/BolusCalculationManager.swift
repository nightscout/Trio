import CoreData
import Foundation
import Swinject

protocol BolusCalculationManager {
    func calculateInsulin(input: CalculationInput) async -> CalculationResult
    func handleBolusCalculation(carbs: Decimal, useFattyMealCorrection: Bool, useSuperBolus: Bool) async -> CalculationResult
}

final class BaseBolusCalculationManager: BolusCalculationManager, Injectable {
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var fileStorage: FileStorage!
    @Injected() private var determinationStorage: DeterminationStorage!

    let glucoseFetchContext = CoreDataStack.shared.newTaskContext()
    let determinationFetchContext = CoreDataStack.shared.newTaskContext()

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
        var insulin: Decimal
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
        let now = Date()
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current

        let regexWithSeconds = #"^\d{2}:\d{2}:\d{2}$"#

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

        for (index, entry) in entries.enumerated() {
            // Dynamically set the format based on whether it matches the regex
            if entry.start.range(of: regexWithSeconds, options: .regularExpression) != nil {
                dateFormatter.dateFormat = "HH:mm:ss"
            } else {
                dateFormatter.dateFormat = "HH:mm"
            }

            guard let entryTime = dateFormatter.date(from: entry.start) else {
                print("Invalid entry start time: \(entry.start)")
                continue
            }

            let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
            let entryStartTime = calendar.date(
                bySettingHour: entryComponents.hour!,
                minute: entryComponents.minute!,
                second: entryComponents.second ?? 0, // Set seconds to 0 if not provided
                of: now
            )!

            let entryEndTime: Date
            if index < entries.count - 1 {
                // Dynamically set the format again for the next element
                if entries[index + 1].start.range(of: regexWithSeconds, options: .regularExpression) != nil {
                    dateFormatter.dateFormat = "HH:mm:ss"
                } else {
                    dateFormatter.dateFormat = "HH:mm"
                }

                if let nextEntryTime = dateFormatter.date(from: entries[index + 1].start) {
                    let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                    entryEndTime = calendar.date(
                        bySettingHour: nextEntryComponents.hour!,
                        minute: nextEntryComponents.minute!,
                        second: nextEntryComponents.second ?? 0,
                        of: now
                    )!
                } else {
                    entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                }
            } else {
                entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
            }

            if now >= entryStartTime, now < entryEndTime {
                return entry.value
            }
        }
        return 0
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
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: glucoseFetchContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: 288
        )

        return await glucoseFetchContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else { return [] }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Updates glucose-related variables based on recent readings
    /// - Parameter objects: Array of GlucoseStored objects
    /// - Returns: GlucoseVariables containing current blood glucose and delta
    private func updateGlucoseVariables(with objects: [GlucoseStored]) -> GlucoseVariables {
        let lastGlucose = objects.first?.glucose ?? 0
        let thirdLastGlucose = objects.dropFirst(2).first?.glucose ?? 0
        let delta = Decimal(lastGlucose) - Decimal(thirdLastGlucose)

        return GlucoseVariables(currentBG: Decimal(lastGlucose), deltaBG: delta)
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
                insulin: 0,
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
            insulin: (mostRecentDetermination.insulinForManualBolus ?? 0) as Decimal,
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
        useSuperBolus: Bool
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
            let glucoseIds = try await fetchGlucose()
            let glucoseObjects: [GlucoseStored] = try await CoreDataStack.shared.getNSManagedObject(
                with: glucoseIds,
                context: glucoseFetchContext
            )
            let glucoseVars = await glucoseFetchContext.perform {
                self.updateGlucoseVariables(with: glucoseObjects)
            }

            // Fetch determination data
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

            return CalculationInput(
                carbs: carbs,
                currentBG: glucoseVars.currentBG,
                deltaBG: glucoseVars.deltaBG,
                target: bolusVars.target,
                isf: bolusVars.isf,
                carbRatio: bolusVars.carbRatio,
                iob: bolusVars.iob,
                cob: bolusVars.cob,
                useFattyMealCorrectionFactor: useFattyMealCorrection,
                fattyMealFactor: settings.fattyMealFactor,
                useSuperBolus: useSuperBolus,
                sweetMealFactor: settings.sweetMealFactor,
                basal: bolusVars.basal,
                fraction: settings.fraction,
                maxBolus: maxBolus,
                maxIOB: maxIOB,
                maxCOB: maxCOB,
                minPredBG: bolusVars.minPredBG
            )
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Error preparing calculation input: \(error.localizedDescription)"
            )
            // Return default values in case of error
            throw error
        }
    }

    /// Calculates the recommended insulin dose based on various parameters
    /// - Parameter input: CalculationInput containing all necessary parameters
    /// - Returns: CalculationResult with detailed breakdown of the calculation
    func calculateInsulin(input: CalculationInput) async -> CalculationResult {
        // insulin needed for the current blood glucose
        let targetDifference = input.currentBG - input.target

        let targetDifferenceInsulin = targetDifference / input.isf

        // more or less insulin because of bg trend in the last 15 minutes
        let fifteenMinutesInsulin = input.deltaBG / input.isf

        // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
        let wholeCob = min(Decimal(input.cob) + input.carbs, input.maxCOB)
        let wholeCobInsulin = wholeCob / input.carbRatio

        // determine how much the calculator reduces/ increases the bolus because of IOB
        let iobInsulinReduction = (-1) * input.iob

        // adding everything together
        // add a calc for the case that no fifteenMinInsulin is available
        let wholeCalc: Decimal
        if input.deltaBG != 0 {
            wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinutesInsulin)
        } else {
            // add (rare) case that no glucose value is available -> maybe display warning?
            // if no bg is available, ?? sets its value to 0
            if input.currentBG == 0 {
                wholeCalc = (iobInsulinReduction + wholeCobInsulin)
            } else {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
            }
        }

        // apply custom factor at the end of the calculations
        // apply custom factor if fatty meal toggle in bolus calc config settings is on and the box for fatty meals is checked (in RootView)
        var factoredInsulin = wholeCalc * input.fraction
        var superBolusInsulin: Decimal = 0
        if input.useFattyMealCorrectionFactor {
            factoredInsulin *= input.fattyMealFactor
        } else if input.useSuperBolus {
            superBolusInsulin = input.sweetMealFactor * input.basal
            factoredInsulin += superBolusInsulin
        }

        // the final result for recommended insulin amount
        var insulinCalculated: Decimal
        let isLoopStale = Date().timeIntervalSince(apsManager.lastLoopDate) > 15 * 60

        // don't recommend insulin when current glucose or minPredBG is < 54 or last sucessful loop was over 15 minutes ago
        if input.currentBG < 54 || input.minPredBG < 54 || isLoopStale {
            insulinCalculated = 0
        } else {
            // no negative insulinCalculated
            insulinCalculated = max(factoredInsulin, 0)
            // don't exceed maxBolus
            insulinCalculated = min(insulinCalculated, input.maxBolus)
            // don't exceed maxIOB
            insulinCalculated = min(insulinCalculated, input.maxIOB - input.iob)
            // round calculated recommendation to allowed bolus increment
            insulinCalculated = apsManager.roundBolus(amount: insulinCalculated)
        }

        return CalculationResult(
            insulinCalculated: insulinCalculated,
            factoredInsulin: factoredInsulin,
            wholeCalc: wholeCalc,
            correctionInsulin: targetDifferenceInsulin,
            iobInsulinReduction: iobInsulinReduction,
            superBolusInsulin: superBolusInsulin,
            targetDifference: targetDifference,
            targetDifferenceInsulin: targetDifferenceInsulin,
            fifteenMinutesInsulin: fifteenMinutesInsulin,
            wholeCob: wholeCob,
            wholeCobInsulin: wholeCobInsulin
        )
    }

    /// Handles the complete bolus calculation process
    /// - Parameters:
    ///   - carbs: Amount of carbohydrates to be consumed
    ///   - useFattyMealCorrection: Whether to apply fatty meal correction
    ///   - useSuperBolus: Whether to use super bolus calculation
    /// - Returns: CalculationResult containing the calculated insulin dose and details
    func handleBolusCalculation(
        carbs: Decimal,
        useFattyMealCorrection: Bool,
        useSuperBolus: Bool
    ) async -> CalculationResult {
        do {
            let input = try await prepareCalculationInput(
                carbs: carbs,
                useFattyMealCorrection: useFattyMealCorrection,
                useSuperBolus: useSuperBolus
            )
            let result = await calculateInsulin(input: input)
            return result
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Error in bolus calculation: \(error.localizedDescription)"
            )
            // Return safe default values
            return CalculationResult(
                insulinCalculated: 0,
                factoredInsulin: 0,
                wholeCalc: 0,
                correctionInsulin: 0,
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

/// Input parameters required for bolus calculation
struct CalculationInput: Sendable {
    let carbs: Decimal // Carbohydrates to be consumed (in grams)
    let currentBG: Decimal // Current blood glucose level
    let deltaBG: Decimal // Blood glucose change in last 15 minutes
    let target: Decimal // Target blood glucose level
    let isf: Decimal // Insulin Sensitivity Factor
    let carbRatio: Decimal // Carb to insulin ratio
    let iob: Decimal // Insulin on Board
    let cob: Int16 // Carbs on Board
    let useFattyMealCorrectionFactor: Bool // Whether to apply fatty meal correction
    let fattyMealFactor: Decimal // Factor for fatty meal adjustment
    let useSuperBolus: Bool // Whether to use super bolus calculation
    let sweetMealFactor: Decimal // Factor for sweet meal adjustment
    let basal: Decimal // Current basal rate
    let fraction: Decimal // General correction factor
    let maxBolus: Decimal // Maximum allowed bolus
    let maxIOB: Decimal // Maximum allowed IOB to be used for rec. bolus calculation
    let maxCOB: Decimal // Maximum allowed COB to be used for rec. bolus calculation
    let minPredBG: Decimal // Minimum Predicted Glucose determined by Oref
}

/// Results of the bolus calculation
struct CalculationResult: Sendable {
    let insulinCalculated: Decimal // Final calculated insulin amount which respects limits
    let factoredInsulin: Decimal // Total calculation after adjustments
    let wholeCalc: Decimal // Total calculation before adjustments
    let correctionInsulin: Decimal // Insulin for BG correction
    let iobInsulinReduction: Decimal // IOB reduction amount
    let superBolusInsulin: Decimal // Additional insulin for super bolus
    let targetDifference: Decimal // Difference from target BG
    let targetDifferenceInsulin: Decimal // Insulin needed for target difference
    let fifteenMinutesInsulin: Decimal // Trend-based insulin adjustment
    let wholeCob: Decimal // Total carbs (COB + new carbs)
    let wholeCobInsulin: Decimal // Insulin needed for total carbs
}
