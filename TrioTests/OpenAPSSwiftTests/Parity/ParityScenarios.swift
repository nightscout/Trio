import Foundation
@testable import Trio

struct ParityScenario {
    let name: String
    let clock: Date
    let glucose: [BloodGlucose]
    let pumpHistory: [PumpHistoryEvent]
    let carbs: [CarbsEntry]
    let tempTargets: [TempTarget]
    let preferences: Preferences
    let orefVariables: TrioCustomOrefVariables
    let currentTemp: TempBasal
    let reservoir: Decimal
    let pumpSettings: PumpSettings
    let bgTargets: BGTargets
    let basalProfile: [BasalProfileEntry]
    let isf: InsulinSensitivities
    let carbRatios: CarbRatios
    let model: String
}

struct ParityPipelineOutputs {
    let profile: Profile
    let autosens: Autosens
    let meal: ComputedCarbs?
    let iob: [IobResult]
    let determination: Determination?
}

enum ParityScenarios {
    static let summerClock = Date.from(isoString: "2026-06-17T14:30:00+02:00")
    static let winterClock = Date.from(isoString: "2026-01-14T14:30:00+01:00")

    static let allNames: [String] = [
        "low-bg-falling",
        "high-bg-rising-smb",
        "post-meal-cob-active",
        "temp-target-active",
        "override-active",
        "dynamic-isf-logarithmic",
        "dynamic-isf-sigmoid",
        "autosens-resistance",
        "autosens-sensitivity",
        "smb-disabled-temp-only",
        "suspend-resume",
        "dense-pump-history-24h",
        "stale-bg-error",
        "winter-standard-time"
    ]

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func build(_ name: String) -> ParityScenario {
        let clock = name == "winter-standard-time" ? winterClock : summerClock

        var preferences = Preferences()
        preferences.maxIOB = 6
        preferences.enableSMBAlways = true
        preferences.enableUAM = true

        var glucoseValues = ParityInputs.values24h(base: 110, tail: [124, 128, 133, 139, 144, 150])
        var pumpHistory = ParityInputs.densePumpHistory(clock: clock)
        var carbs: [CarbsEntry] = []
        var tempTargets: [TempTarget] = []
        var orefVariables = ParityInputs.orefVariables(clock: clock)
        var currentTemp = TempBasal(duration: 30, rate: 0.75, temp: .absolute, timestamp: clock.addingTimeInterval(-5 * 60))
        var glucoseClock = clock

        switch name {
        case "low-bg-falling":
            glucoseValues = ParityInputs.values24h(base: 105, tail: [92, 88, 84, 80, 76, 72, 68])
        case "high-bg-rising-smb",
             "winter-standard-time":
            glucoseValues = ParityInputs.values24h(base: 120, tail: [170, 178, 186, 194, 202, 210])
        case "post-meal-cob-active":
            preferences.enableSMBWithCOB = true
            carbs = [CarbsEntry.forTest(createdAt: clock.addingTimeInterval(-40 * 60), carbs: 45)]
            glucoseValues = ParityInputs.values24h(base: 108, tail: [110, 112, 118, 126, 136, 148, 158, 165])
        case "temp-target-active":
            preferences.highTemptargetRaisesSensitivity = true
            tempTargets = [TempTarget(
                id: "tt-1",
                name: "Activity",
                createdAt: clock.addingTimeInterval(-30 * 60),
                targetTop: 130,
                targetBottom: 130,
                duration: 90,
                enteredBy: "Trio",
                reason: "Activity",
                isPreset: nil,
                enabled: true,
                halfBasalTarget: 160
            )]
        case "override-active":
            orefVariables = TrioCustomOrefVariables(
                average_total_data: 0,
                weightedAverage: 0,
                currentTDD: 0,
                past2hoursAverage: 0,
                date: clock,
                overridePercentage: 130,
                useOverride: true,
                duration: 120,
                unlimited: false,
                overrideTarget: 90,
                smbIsOff: false,
                advancedSettings: false,
                isfAndCr: true,
                isf: true,
                cr: true,
                smbIsScheduledOff: false,
                start: 0,
                end: 0,
                smbMinutes: 30,
                uamMinutes: 30
            )
        case "dynamic-isf-logarithmic",
             "dynamic-isf-sigmoid":
            preferences.useNewFormula = true
            preferences.sigmoid = name == "dynamic-isf-sigmoid"
            preferences.adjustmentFactor = 0.8
            preferences.adjustmentFactorSigmoid = 0.6
            preferences.tddAdjBasal = true
            orefVariables = TrioCustomOrefVariables(
                average_total_data: 35.8,
                weightedAverage: 36.2,
                currentTDD: 38.5,
                past2hoursAverage: 3.1,
                date: clock,
                overridePercentage: 100,
                useOverride: false,
                duration: 0,
                unlimited: false,
                overrideTarget: 0,
                smbIsOff: false,
                advancedSettings: false,
                isfAndCr: false,
                isf: false,
                cr: false,
                smbIsScheduledOff: false,
                start: 0,
                end: 0,
                smbMinutes: 30,
                uamMinutes: 30
            )
        case "autosens-resistance":
            glucoseValues = ParityInputs.drift24h(from: 100, to: 185)
        case "autosens-sensitivity":
            glucoseValues = ParityInputs.drift24h(from: 160, to: 88)
        case "smb-disabled-temp-only":
            preferences.enableSMBAlways = false
            preferences.enableUAM = false
            preferences.maxIOB = 5
        case "suspend-resume":
            preferences.suspendZerosIOB = true
            pumpHistory = ParityInputs.lightPumpHistory(clock: clock)
            pumpHistory
                .append(PumpHistoryEvent(id: "suspend-s", type: .pumpSuspend, timestamp: clock.addingTimeInterval(-3 * 3600)))
            pumpHistory
                .append(PumpHistoryEvent(id: "resume-s", type: .pumpResume, timestamp: clock.addingTimeInterval(-1 * 3600)))
        case "dense-pump-history-24h":
            carbs = [
                CarbsEntry.forTest(createdAt: clock.addingTimeInterval(-5 * 3600), carbs: 60),
                CarbsEntry.forTest(createdAt: clock.addingTimeInterval(-10 * 3600), carbs: 30)
            ]
        case "stale-bg-error":
            glucoseClock = clock.addingTimeInterval(-25 * 60)
            currentTemp = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: clock.addingTimeInterval(-3600))
        default:
            break
        }

        return ParityScenario(
            name: name,
            clock: clock,
            glucose: ParityInputs.trace(endingAt: glucoseClock, values: glucoseValues),
            pumpHistory: pumpHistory,
            carbs: carbs,
            tempTargets: tempTargets,
            preferences: preferences,
            orefVariables: orefVariables,
            currentTemp: currentTemp,
            reservoir: 150,
            pumpSettings: ParityInputs.pumpSettings(),
            bgTargets: ParityInputs.bgTargets(),
            basalProfile: ParityInputs.basalProfile(),
            isf: ParityInputs.isf(),
            carbRatios: ParityInputs.carbRatios(),
            model: "554"
        )
    }

    /// Mirrors the production Swift path: OpenAPSSwift.makeProfile → autosense
    /// (8h/24h, min ratio) → meal → iob (deduped suspend/resume) → determineBasal.
    static func runPipeline(_ scenario: ParityScenario) throws -> ParityPipelineOutputs {
        let profile = try ProfileGenerator.generate(
            pumpSettings: scenario.pumpSettings,
            bgTargets: scenario.bgTargets,
            basalProfile: scenario.basalProfile,
            isf: scenario.isf,
            preferences: scenario.preferences,
            carbRatios: scenario.carbRatios,
            tempTargets: scenario.tempTargets,
            model: scenario.model,
            clock: scenario.clock
        )

        let ratio8h = try AutosensGenerator.generate(
            glucose: scenario.glucose,
            pumpHistory: scenario.pumpHistory,
            basalProfile: scenario.basalProfile,
            profile: profile,
            carbs: scenario.carbs,
            tempTargets: scenario.tempTargets,
            maxDeviations: 96,
            clock: scenario.clock,
            includeDeviationsForTesting: true
        )
        let ratio24h = try AutosensGenerator.generate(
            glucose: scenario.glucose,
            pumpHistory: scenario.pumpHistory,
            basalProfile: scenario.basalProfile,
            profile: profile,
            carbs: scenario.carbs,
            tempTargets: scenario.tempTargets,
            maxDeviations: 288,
            clock: scenario.clock,
            includeDeviationsForTesting: true
        )
        let autosens = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h

        let meal = try MealGenerator.generate(
            pumpHistory: scenario.pumpHistory,
            profile: profile,
            basalProfile: scenario.basalProfile,
            clock: scenario.clock,
            carbHistory: scenario.carbs,
            glucoseHistory: scenario.glucose
        )

        let iob = try IobGenerator.generate(
            history: scenario.pumpHistory.removingDuplicateSuspendResumeEvents(),
            profile: profile,
            clock: scenario.clock,
            autosens: autosens
        )

        guard let mealData = meal else {
            throw ParityError("meal generation returned nil for \(scenario.name)")
        }

        let determination = try DeterminationGenerator.generate(
            profile: profile,
            preferences: scenario.preferences,
            currentTemp: scenario.currentTemp,
            iobData: iob,
            mealData: mealData,
            autosensData: autosens,
            reservoirData: scenario.reservoir,
            glucose: scenario.glucose,
            microBolusAllowed: true,
            trioCustomOrefVariables: scenario.orefVariables,
            currentTime: scenario.clock
        )

        return ParityPipelineOutputs(
            profile: profile,
            autosens: autosens,
            meal: meal,
            iob: iob,
            determination: determination
        )
    }
}
