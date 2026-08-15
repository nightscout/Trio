import Foundation
import Testing
@testable import Trio

/// Wall-clock timings for the oref-swift generators. Skipped unless
/// TEST_RUNNER_TRIO_RUN_PERF=1 is set; numbers are compared manually
/// before/after optimization on the same machine.
@Suite(
    "OpenAPSSwift performance",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["TRIO_RUN_PERF"] == "1")
) struct ParityPerformanceTests {
    private func measure(_ label: String, iterations: Int = 10, _ body: () throws -> Void) rethrows {
        let clock = ContinuousClock()
        try body() // warm-up
        var durations: [Duration] = []
        for _ in 0 ..< iterations {
            durations.append(try clock.measure(body))
        }
        durations.sort()
        let toMs = { (duration: Duration) -> Double in
            Double(duration.components.seconds) * 1000 +
                Double(duration.components.attoseconds) / 1E15
        }
        print(String(
            format: "[perf] %@ min %.2f ms / median %.2f ms (n=%d)",
            label,
            toMs(durations.first!),
            toMs(durations[durations.count / 2]),
            iterations
        ))
    }

    @Test("generator timings on dense 24h history") func generatorTimings() throws {
        let scenario = ParityScenarios.build("dense-pump-history-24h")
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
        let dedupedHistory = scenario.pumpHistory.removingDuplicateSuspendResumeEvents()

        try measure("IobGenerator.generate") {
            _ = try IobGenerator.generate(
                history: dedupedHistory,
                profile: profile,
                clock: scenario.clock,
                autosens: nil
            )
        }

        try measure("AutosensGenerator.generate(288)") {
            _ = try AutosensGenerator.generate(
                glucose: scenario.glucose,
                pumpHistory: scenario.pumpHistory,
                basalProfile: scenario.basalProfile,
                profile: profile,
                carbs: scenario.carbs,
                tempTargets: scenario.tempTargets,
                maxDeviations: 288,
                clock: scenario.clock
            )
        }

        try measure("MealGenerator.generate") {
            _ = try MealGenerator.generate(
                pumpHistory: scenario.pumpHistory,
                profile: profile,
                basalProfile: scenario.basalProfile,
                clock: scenario.clock,
                carbHistory: scenario.carbs,
                glucoseHistory: scenario.glucose
            )
        }

        try measure("full pipeline") {
            _ = try ParityScenarios.runPipeline(scenario)
        }
    }
}
