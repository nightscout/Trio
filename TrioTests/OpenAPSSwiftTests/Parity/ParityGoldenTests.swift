import Foundation
import Testing
@testable import Trio

@Suite(
    "OpenAPSSwift golden parity",
    .serialized,
    .enabled(if: ParityEnv.isPinned, "goldens require the process to run in \(ParityEnv.timeZoneIdentifier)")
) struct ParityGoldenTests {
    @Test(
        "pipeline output matches golden",
        arguments: ParityScenarios.allNames
    ) func pipelineMatchesGolden(scenarioName: String) throws {
        let scenario = ParityScenarios.build(scenarioName)
        let outputs = try ParityScenarios.runPipeline(scenario)

        try ParityHarness.check(
            ParityHarness.canonicalJSON(outputs.profile),
            scenario: scenarioName,
            stage: "profile"
        )
        try ParityHarness.check(
            ParityHarness.canonicalJSON(outputs.autosens),
            scenario: scenarioName,
            stage: "autosens"
        )
        try ParityHarness.check(
            ParityHarness.canonicalJSON(outputs.meal),
            scenario: scenarioName,
            stage: "meal"
        )
        try ParityHarness.check(
            ParityHarness.canonicalJSON(outputs.iob),
            scenario: scenarioName,
            stage: "iob"
        )
        try ParityHarness.check(
            ParityHarness.normalizeDeterminationId(ParityHarness.canonicalJSON(outputs.determination)),
            scenario: scenarioName,
            stage: "determination"
        )

        if ParityHarness.isRecording {
            Issue.record("goldens recorded for \(scenarioName) — re-run without TRIO_RECORD_GOLDENS to compare")
        }
    }
}
