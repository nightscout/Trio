import Foundation
import Testing

@testable import Trio

/// ⚠️ NOTE:
/// If tests in this suite are failing unexpectedly (e.g. sudden unexplainable mismatches for decimal places for calculated values),
/// try running the test suite on a clean simulator.
///
/// You can reset the simulator from the menu: **Device > Erase All Content and Settings**
/// or by launching with `-com.apple.CoreData.SQLDebug 1` for more insight into the issue.
///
@Suite("Bolus Calculator Tests") struct BolusCalculatorTests: Injectable {
    @Injected() var calculator: BolusCalculationManager!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var fileStorage: FileStorage!
    @Injected() var apsManager: APSManager!
    let resolver = TrioApp().resolver

    init() {
        injectServices(resolver)
    }

    @Test("Calculator is correctly initialized") func testCalculatorInitialization() {
        #expect(calculator != nil, "BolusCalculationManager should be injected")
        #expect(calculator is BaseBolusCalculationManager, "Calculator should be of type BaseBolusCalculationManager")
    }

    @Test("Calculate insulin for standard meal") func testStandardMealCalculation() async throws {
        // STEP 1: Setup test scenario
        // We need to provide a CalculationInput struct
        let carbs: Decimal = 80
        let currentBG: Decimal = 180 // 80 points above target, should result in 2U correction
        let deltaBG: Decimal = 5 // Rising trend, should add small correction
        let target: Decimal = 100
        let isf: Decimal = 40
        let carbRatio: Decimal = 10 // Should result in 8U for carbs
        let iob: Decimal = 1.0 // Should subtract from final result
        let cob: Int16 = 20
        let useFattyMealCorrectionFactor: Bool = false
        let useSuperBolus: Bool = false
        let fattyMealFactor: Decimal = 0.8
        let sweetMealFactor: Decimal = 2
        let basal: Decimal = 1.5
        let fraction: Decimal = 0.8
        let maxBolus: Decimal = 10
        let maxIOB: Decimal = 15.0
        let maxCOB: Decimal = 120.0
        let minPredBG: Decimal = 80.0

        // STEP 2: Create calculation input
        let input = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: useFattyMealCorrectionFactor,
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: useSuperBolus,
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: minPredBG,
            lastLoopDate: Date()
        )

        // STEP 3: Calculate insulin
        let result = await calculator.calculateInsulin(input: input)

        // STEP 4: Verify results
        // Expected calculation breakdown:
        // wholeCob = 80g + 20g COB = 100g
        // wholeCobInsulin = 100g ÷ 10 g/U = 10U
        // targetDifference = currentBG - target = 180 - 100 = 80 mg/dL
        // targetDifferenceInsulin = 80 mg/dL ÷ 40 mg/dL/U = 2U
        // fifteenMinutesInsulin = 5 mg/dL ÷ 40 mg/dL/U = 0.125U
        // correctionInsulin = targetDifferenceInsulin = 2U
        // iobInsulinReduction = 1U
        // superBolusInsulin = 0U (disabled)
        // no adjustment for fatty meals (disabled)
        // wholeCalc = round(wholeCobInsulin + correctionInsulin + fifteenMinutesInsulin - iobInsulinReduction, 3) = 11.125U
        // insulinCalculated = round(wholeCalc × fraction, 3) = 8.9U

        // Calculate expected values with proper rounding using roundBolus method from the apsManager
        let wholeCobInsulin = apsManager.roundBolus(amount: Decimal(100) / Decimal(10)) // 10U
        let targetDifferenceInsulin = apsManager.roundBolus(amount: Decimal(80) / Decimal(40)) // 2U
        let fifteenMinutesInsulin = apsManager.roundBolus(amount: Decimal(5) / Decimal(40)) // 0.125U
        let wholeCalc = wholeCobInsulin + targetDifferenceInsulin + fifteenMinutesInsulin - Decimal(1) // 11.125U
        let expectedInsulinCalculated = apsManager.roundBolus(amount: wholeCalc * fraction) // 8.9U

        #expect(
            result.insulinCalculated == expectedInsulinCalculated,
            """
            Incorrect insulin calculation
            Expected: \(expectedInsulinCalculated)U
            Actual: \(result.insulinCalculated)U
            Components from CalculationResult:
            - insulinCalculated: \(result.insulinCalculated)U (expected: \(expectedInsulinCalculated)U)
            - wholeCalc: \(result.wholeCalc)U (expected: \(wholeCalc)U)
            - correctionInsulin: \(result.correctionInsulin)U (expected: \(targetDifferenceInsulin)U)
            - iobInsulinReduction: \(result.iobInsulinReduction)U (expected: 1U)
            - superBolusInsulin: \(result.superBolusInsulin)U (expected: 0U)
            - targetDifference: \(result.targetDifference) mg/dL (expected: 80 mg/dL)
            - targetDifferenceInsulin: \(result.targetDifferenceInsulin)U (expected: \(targetDifferenceInsulin)U)
            - fifteenMinutesInsulin: \(result.fifteenMinutesInsulin)U (expected: \(fifteenMinutesInsulin)U)
            - wholeCob: \(result.wholeCob)g (expected: 100g)
            - wholeCobInsulin: \(result.wholeCobInsulin)U (expected: \(wholeCobInsulin)U)
            """
        )

        // Verify each component from CalculationResult struct with rounded values
        #expect(
            result.insulinCalculated == expectedInsulinCalculated,
            "Final calculated insulin amount should be \(expectedInsulinCalculated)U"
        )
        #expect(result.wholeCalc == wholeCalc, "Total calculation before fraction should be \(wholeCalc)U")
        #expect(
            result.correctionInsulin == targetDifferenceInsulin,
            "Insulin for BG correction should be \(targetDifferenceInsulin)U"
        )
        #expect(result.iobInsulinReduction == -1.0, "Absolute IOB reduction amount should be 1U, hence -1U")
        #expect(result.superBolusInsulin == 0, "Additional insulin for super bolus should be 0U")
        #expect(result.targetDifference == 80, "Difference from target BG should be 80 mg/dL")
        #expect(
            result.targetDifferenceInsulin == targetDifferenceInsulin,
            "Insulin needed for target difference should be \(targetDifferenceInsulin)U"
        )
        #expect(
            result.fifteenMinutesInsulin == fifteenMinutesInsulin,
            "Trend-based insulin adjustment should be \(fifteenMinutesInsulin)U"
        )
        #expect(result.wholeCob == 100, "Total carbs (COB + new carbs) should be 100g")
        #expect(result.wholeCobInsulin == wholeCobInsulin, "Insulin for total carbs should be \(wholeCobInsulin)U")
    }

    @Test("Calculate insulin for fatty meal") func testFattyMealCalculation() async throws {
        // STEP 1: Setup test scenario
        // We need to provide a CalculationInput struct
        let carbs: Decimal = 80
        let currentBG: Decimal = 180 // 80 points above target, should result in 2U correction
        let deltaBG: Decimal = 5 // Rising trend, should add small correction
        let target: Decimal = 100
        let isf: Decimal = 40
        let carbRatio: Decimal = 10 // Should result in 8U for carbs
        let iob: Decimal = 1.0 // Should subtract from final result
        let cob: Int16 = 20
        let useFattyMealCorrectionFactor: Bool = true // now set to true
        let useSuperBolus: Bool = false
        let fattyMealFactor: Decimal = 0.8
        let sweetMealFactor: Decimal = 2
        let basal: Decimal = 1.5
        let fraction: Decimal = 0.8
        let maxBolus: Decimal = 10
        let maxIOB: Decimal = 15.0
        let maxCOB: Decimal = 120.0
        let minPredBG: Decimal = 80.0

        // STEP 2: Create calculation input
        let input = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: useFattyMealCorrectionFactor,
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: useSuperBolus,
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: minPredBG,
            lastLoopDate: Date()
        )

        // STEP 3: Calculate insulin with fatty meal enabled
        let fattyMealResult = await calculator.calculateInsulin(input: input)

        // STEP 4: Calculate insulin with fatty meal disabled for comparison
        let standardInput = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: false, // Disabled for comparison
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: useSuperBolus,
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: minPredBG,
            lastLoopDate: Date()
        )
        let standardResult = await calculator.calculateInsulin(input: standardInput)

        // STEP 5: Verify results
        // Fatty meal should reduce the insulin amount by the fatty meal factor (0.8)
        let expectedReduction = fattyMealFactor
        let actualReduction = Decimal(
            (Double(fattyMealResult.insulinCalculated) / Double(standardResult.insulinCalculated) * 10.0).rounded() / 10.0
        )

        #expect(
            actualReduction == expectedReduction,
            """
            Fatty meal calculation incorrect
            Expected reduction factor: \(expectedReduction)
            Actual reduction factor: \(actualReduction)
            Standard calculation: \(standardResult.insulinCalculated)U
            Fatty meal calculation: \(fattyMealResult.insulinCalculated)U
            """
        )
    }

    @Test("Calculate insulin with super bolus") func testSuperBolusCalculation() async throws {
        // STEP 1: Setup test scenario
        // We need to provide a CalculationInput struct
        let carbs: Decimal = 80
        let currentBG: Decimal = 180 // 80 points above target, should result in 2U correction
        let deltaBG: Decimal = 5 // Rising trend, should add small correction
        let target: Decimal = 100
        let isf: Decimal = 40
        let carbRatio: Decimal = 10 // Should result in 8U for carbs
        let iob: Decimal = 1.0 // Should subtract from final result
        let cob: Int16 = 20
        let useFattyMealCorrectionFactor: Bool = false
        let useSuperBolus: Bool = true // Super bolus enabled
        let fattyMealFactor: Decimal = 0.8
        let sweetMealFactor: Decimal = 2
        let basal: Decimal = 1.5 // Will be added to insulin calculation when super bolus is enabled
        let fraction: Decimal = 0.8
        let maxBolus: Decimal = 10
        let maxIOB: Decimal = 15.0
        let maxCOB: Decimal = 120.0
        let minPredBG: Decimal = 80.0

        // STEP 2: Create calculation input with super bolus enabled
        let input = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: useFattyMealCorrectionFactor,
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: useSuperBolus,
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: minPredBG,
            lastLoopDate: Date()
        )

        // STEP 3: Calculate insulin with super bolus enabled
        let superBolusResult = await calculator.calculateInsulin(input: input)

        // STEP 4: Calculate insulin with super bolus disabled for comparison
        let standardInput = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: useFattyMealCorrectionFactor,
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: false, // Disabled for comparison
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: minPredBG,
            lastLoopDate: Date()
        )
        let standardResult = await calculator.calculateInsulin(input: standardInput)

        // STEP 5: Verify results
        // Super bolus should add basal rate * sweetMealFactor to the insulin calculation
        let expectedSuperBolusInsulin = basal * sweetMealFactor
        #expect(
            superBolusResult.superBolusInsulin == expectedSuperBolusInsulin,
            """
            Super bolus insulin incorrect
            Expected: \(expectedSuperBolusInsulin)U (basal \(basal)U × sweetMealFactor \(sweetMealFactor))
            Actual: \(superBolusResult.superBolusInsulin)U
            """
        )

        #expect(
            superBolusResult.insulinCalculated > standardResult.insulinCalculated,
            """
            Super bolus calculation incorrect
            Expected super bolus calculation to be higher than standard
            Super bolus: \(superBolusResult.insulinCalculated)U
            Standard: \(standardResult.insulinCalculated)U
            Difference: \(superBolusResult.insulinCalculated - standardResult.insulinCalculated)U
            """
        )

        // The difference should be the difference of super bolus (= standard dose + the basal rate * sweetMealFactor) limited by max bolus, and the standard dose.
        let actualDifference = (superBolusResult.insulinCalculated - standardResult.insulinCalculated)
        let expectedDifference = min(superBolusResult.insulinCalculated, maxBolus) - standardResult.insulinCalculated
        #expect(
            actualDifference == expectedDifference,
            """
            Super bolus difference incorrect
            Expected difference: min(\(expectedSuperBolusInsulin), \(maxBolus)) U (basal \(basal)U × sweetMealFactor \(sweetMealFactor) + standard dose \(standardResult
                .insulinCalculated)) - standard dose \(standardResult.insulinCalculated)
            Actual difference: \(actualDifference)U
            Standard result: \(standardResult)
            SuperBolus result: \(superBolusResult)
            """
        )
    }

    @Test("Calculate insulin with low glucose forecast (minPredBG < 54)") func testMinPredBGGuardBolusCalculation() async throws {
        // STEP 1: Setup test scenario
        // We need to provide a CalculationInput struct
        let carbs: Decimal = 80
        let currentBG: Decimal = 180 // 80 points above target, should result in 2U correction
        let deltaBG: Decimal = 5 // Rising trend, should add small correction
        let target: Decimal = 100
        let isf: Decimal = 40
        let carbRatio: Decimal = 10 // Should result in 8U for carbs
        let iob: Decimal = 1.0 // Should subtract from final result
        let cob: Int16 = 20
        let useFattyMealCorrectionFactor: Bool = false
        let useSuperBolus: Bool = false
        let fattyMealFactor: Decimal = 0.8
        let sweetMealFactor: Decimal = 2
        let basal: Decimal = 1.5 // Will be added to insulin calculation when super bolus is enabled
        let fraction: Decimal = 0.8
        let maxBolus: Decimal = 10
        let maxIOB: Decimal = 15.0
        let maxCOB: Decimal = 120.0
        let minPredBG: Decimal = 45.0 // Severe Hypo forecasted

        // STEP 2: Create calculation input with severe hypo forecasted minPredBG
        let input = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: useFattyMealCorrectionFactor,
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: useSuperBolus,
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: minPredBG,
            lastLoopDate: Date()
        )

        // STEP 3: Calculate insulin with super bolus enabled
        let minPredBGResult = await calculator.calculateInsulin(input: input)

        // STEP 4: Calculate insulin with super bolus disabled for comparison
        let standardInput = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: useFattyMealCorrectionFactor,
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: false, // Disabled for comparison
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: 80,
            lastLoopDate: Date()
        )
        let standardResult = await calculator.calculateInsulin(input: standardInput)

        // STEP 5: Verify results
        #expect(minPredBGResult.insulinCalculated == 0, "Severe Hypo forecasted; insulin calculated set to 0 U for safety!")

        #expect(
            standardResult.insulinCalculated > minPredBGResult.insulinCalculated,
            """
            Super bolus calculation incorrect
            Expected super bolus calculation to be higher than standard
            MinPred <54 bolus: \(minPredBGResult.insulinCalculated) U
            Standard: \(standardResult.insulinCalculated) U
            Difference: \(standardResult.insulinCalculated - minPredBGResult.insulinCalculated) U
            """
        )
    }

    @Test("Calculate insulin with stale loop (longer than 15min ago)") func testStaleLoopBolusCalculation() async throws {
        // STEP 1: Setup test scenario
        // We need to provide a CalculationInput struct
        let carbs: Decimal = 80
        let currentBG: Decimal = 180 // 80 points above target, should result in 2U correction
        let deltaBG: Decimal = 5 // Rising trend, should add small correction
        let target: Decimal = 100
        let isf: Decimal = 40
        let carbRatio: Decimal = 10 // Should result in 8U for carbs
        let iob: Decimal = 1.0 // Should subtract from final result
        let cob: Int16 = 20
        let useFattyMealCorrectionFactor: Bool = false
        let useSuperBolus: Bool = false
        let fattyMealFactor: Decimal = 0.8
        let sweetMealFactor: Decimal = 2
        let basal: Decimal = 1.5 // Will be added to insulin calculation when super bolus is enabled
        let fraction: Decimal = 0.8
        let maxBolus: Decimal = 10
        let maxIOB: Decimal = 15.0
        let maxCOB: Decimal = 120.0
        let minPredBG: Decimal = 80

        // STEP 2: Create calculation input with severe hypo forecasted minPredBG
        let input = CalculationInput(
            carbs: carbs,
            currentBG: currentBG,
            deltaBG: deltaBG,
            target: target,
            isf: isf,
            carbRatio: carbRatio,
            iob: iob,
            cob: cob,
            useFattyMealCorrectionFactor: useFattyMealCorrectionFactor,
            fattyMealFactor: fattyMealFactor,
            useSuperBolus: useSuperBolus,
            sweetMealFactor: sweetMealFactor,
            basal: basal,
            fraction: fraction,
            maxBolus: maxBolus,
            maxIOB: maxIOB,
            maxCOB: maxCOB,
            minPredBG: minPredBG,
            lastLoopDate: Date().addingTimeInterval(TimeInterval(-15 * 60)) // 15min ago
        )

        // STEP 3: Calculate insulin with super bolus enabled
        let result = await calculator.calculateInsulin(input: input)

        // STEP 4: Verify results
        #expect(result.insulinCalculated == 0, "Loop is stale; insulin calculated set to 0 U for safety!")
    }

    @Test("Calculate insulin with zero carbs") func testZeroCarbsCalculation() async throws {
        // Given
        let carbs: Decimal = 0

        // When
        let result = await calculator.handleBolusCalculation(
            carbs: carbs,
            useFattyMealCorrection: false,
            useSuperBolus: false,
            lastLoopDate: Date(),
            minPredBG: nil
        )

        // Then
        #expect(result.wholeCobInsulin == 0, "Zero carbs should require no insulin for carbs")
    }

    @Test("Verify settings retrieval") func testGetSettings() async throws {
        // Given - Save original settings to restore later
        let originalSettings = settingsManager.settings

        // Setup test settings
        let expectedUnits = GlucoseUnits.mgdL
        let expectedFraction: Decimal = 0.7
        let expectedFattyMealFactor: Decimal = 0.8
        let expectedSweetMealFactor: Decimal = 2
        let expectedMaxCarbs: Decimal = 150

        // Update settings through settings manager
        settingsManager.settings.units = expectedUnits
        settingsManager.settings.overrideFactor = expectedFraction
        settingsManager.settings.fattyMealFactor = expectedFattyMealFactor
        settingsManager.settings.sweetMealFactor = expectedSweetMealFactor
        settingsManager.settings.maxCarbs = expectedMaxCarbs

        // Save settings to storage
        fileStorage.save(settingsManager.settings, as: OpenAPS.Settings.settings)

        // When
        let (units, fraction, fattyMealFactor, sweetMealFactor, maxCarbs) = await getSettings()

        // Then
        #expect(units == expectedUnits, "Units should match settings")
        #expect(fraction == expectedFraction, "Override factor should match settings")
        #expect(fattyMealFactor == expectedFattyMealFactor, "Fatty meal factor should match settings")
        #expect(sweetMealFactor == expectedSweetMealFactor, "Sweet meal factor should match settings")
        #expect(maxCarbs == expectedMaxCarbs, "Max carbs should match settings")

        // Cleanup - Restore original settings
        settingsManager.settings = originalSettings
        fileStorage.save(originalSettings, as: OpenAPS.Settings.settings)
    }

    @Test("Verify getCurrentSettingValue returns correct values based on time") func testGetCurrentSettingValue() async throws {
        // STEP 1: Backup current settings
        let originalBasalProfile = await fileStorage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
        let originalCarbRatios = await fileStorage.retrieveAsync(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
        let originalBGTargets = await fileStorage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        let originalISFValues = await fileStorage.retrieveAsync(
            OpenAPS.Settings.insulinSensitivities,
            as: InsulinSensitivities.self
        )

        // STEP 2: Setup test data with known values
        // Note: Entries must be sorted by time for the algorithm to work correctly
        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0), // 12:00 AM - 6:00 AM: 1.0
            BasalProfileEntry(start: "06:00", minutes: 360, rate: 1.2), // 6:00 AM - 12:00 PM: 1.2
            BasalProfileEntry(start: "12:00", minutes: 720, rate: 1.1), // 12:00 PM - 6:00 PM: 1.1
            BasalProfileEntry(start: "18:00", minutes: 1080, rate: 0.9) // 6:00 PM - 12:00 AM: 0.9
        ]

        let carbRatios = CarbRatios(
            units: .grams,
            schedule: [
                CarbRatioEntry(start: "00:00", offset: 0, ratio: 10), // 12:00 AM - 12:00 PM: 10
                CarbRatioEntry(start: "12:00", offset: 720, ratio: 12) // 12:00 PM - 12:00 AM: 12
            ]
        )

        let bgTargets = BGTargets(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            targets: [
                BGTargetEntry(low: 100, high: 120, start: "00:00", offset: 0), // 12:00 AM - 8:00 AM: 100
                BGTargetEntry(low: 90, high: 110, start: "08:00", offset: 480) // 8:00 AM - 12:00 AM: 90
            ]
        )

        let isfValues = InsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: [
                InsulinSensitivityEntry(sensitivity: 40, offset: 0, start: "00:00"), // 12:00 AM - 2:00 PM: 40
                InsulinSensitivityEntry(sensitivity: 45, offset: 840, start: "14:00") // 2:00 PM - 12:00 AM: 45
            ]
        )

        // STEP 3: Store test data
        fileStorage.save(basalProfile, as: OpenAPS.Settings.basalProfile)
        fileStorage.save(carbRatios, as: OpenAPS.Settings.carbRatios)
        fileStorage.save(bgTargets, as: OpenAPS.Settings.bgTargets)
        fileStorage.save(isfValues, as: OpenAPS.Settings.insulinSensitivities)

        // STEP 4: Define test cases with specific times and expected values
        // Format: (hour, minute, [setting type: expected value])
        let testTimes: [(hour: Int, minute: Int, expected: [SettingType: Decimal])] = [
            // Test midnight values (00:00)
            (
                hour: 0, minute: 0,
                expected: [
                    .basal: 1.0, // First basal rate
                    .carbRatio: 10, // First carb ratio
                    .bgTarget: 100, // First target
                    .isf: 40 // First ISF
                ]
            ),
            // Test mid-morning values (7:00)
            (
                hour: 7, minute: 0,
                expected: [
                    .basal: 1.2, // Second basal rate (after 6:00)
                    .carbRatio: 10, // Still first carb ratio
                    .bgTarget: 100, // Still first target
                    .isf: 40 // Still first ISF
                ]
            ),
            // Test afternoon values (15:00)
            (
                hour: 15, minute: 0,
                expected: [
                    .basal: 1.1, // Third basal rate (after 12:00)
                    .carbRatio: 12, // Second carb ratio (after 12:00)
                    .bgTarget: 90, // Second target
                    .isf: 45 // Second ISF (after 14:00)
                ]
            )
        ]

        // STEP 5: Test each time point
        for testTime in testTimes {
            // Create a date object for the test time
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = testTime.hour
            components.minute = testTime.minute
            components.second = 0
            guard let testDate = calendar.date(from: components) else {
                throw TestError("Failed to create test date")
            }

            // Test each setting type at this time
            for (type, expectedValue) in testTime.expected {
                // Get the actual value for this setting at the test time
                let value = await getCurrentSettingValue(for: type, at: testDate)

                // Compare with expected value
                #expect(
                    value == expectedValue,
                    """
                    Failed at \(testTime.hour):\(String(format: "%02d", testTime.minute))
                    Setting: \(type)
                    Expected: \(expectedValue)
                    Actual: \(value)
                    """
                )
            }
        }

        // STEP 6: Cleanup - Restore original settings
        if let originalBasalProfile = originalBasalProfile {
            fileStorage.save(originalBasalProfile, as: OpenAPS.Settings.basalProfile)
        }
        if let originalCarbRatios = originalCarbRatios {
            fileStorage.save(originalCarbRatios, as: OpenAPS.Settings.carbRatios)
        }
        if let originalBGTargets = originalBGTargets {
            fileStorage.save(originalBGTargets, as: OpenAPS.Settings.bgTargets)
        }
        if let originalISFValues = originalISFValues {
            fileStorage.save(originalISFValues, as: OpenAPS.Settings.insulinSensitivities)
        }
    }
}

// Copied over from BolusCalculationManager as they are not included in the protocol definition (and I don´t want them to be included)

extension BolusCalculatorTests {
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
    private func getCurrentSettingValue(for type: SettingType, at date: Date) async -> Decimal {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: date)
        let minutesSinceMidnight = calendar.dateComponents([.minute], from: midnight, to: date).minute ?? 0

        switch type {
        case .basal:
            let profile = await getBasalProfile()
            return profile.last { $0.minutes <= minutesSinceMidnight }?.rate ?? 0

        case .carbRatio:
            let ratios = await getCarbRatios()
            return ratios.schedule.last { $0.offset <= minutesSinceMidnight }?.ratio ?? 0

        case .bgTarget:
            let targets = await getBGTargets()
            return targets.targets.last { $0.offset <= minutesSinceMidnight }?.low ?? 0

        case .isf:
            let sensitivities = await getISFValues()
            return sensitivities.sensitivities.last { $0.offset <= minutesSinceMidnight }?.sensitivity ?? 0
        }
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
}
