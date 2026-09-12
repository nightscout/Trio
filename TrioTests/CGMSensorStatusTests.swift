import CGMBLEKit
import Foundation
import G7SensorKit
import Testing

@testable import Trio

@Suite("CGM: CGMSensorStatus mapping") struct CGMSensorStatusTests {
    // MARK: - The states this feature exists for

    /// `temporarySensorIssue` sits behind the G7's "Sensor Issue" highlight.
    @Test("G7 temporarySensorIssue reports a sensor issue, distinct from warmup") func g7TemporarySensorIssueIsReported() {
        let issue = AlgorithmState.known(.temporarySensorIssue).reportableStatus
        #expect(issue?.key == "sensorIssue")
        #expect(AlgorithmState.known(.warmup).reportableStatus == nil)
    }

    /// `questionMarks` is the state behind the receiver's "???".
    @Test("G6 questionMarks maps to the same sensor issue as G7") func g6QuestionMarksMatchesG7() {
        let g6 = CalibrationState.known(.questionMarks).reportableStatus
        let g7 = AlgorithmState.known(.temporarySensorIssue).reportableStatus
        #expect(g6?.key == "sensorIssue")
        #expect(g6?.key == g7?.key)
    }

    // MARK: - Grouping

    /// Variants of one fault share a key so they dedup as a single episode.
    @Test("Faults collapse onto one dedup key per kind") func faultsGroupByKind() {
        let g7Failures: [AlgorithmState.State] = [
            .sensorFailed,
            .sensorFailedDuetoCountsAberration,
            .sensorFailedDuetoResidualAberration,
            .sensorFailedDueToProgressiveSensorDecline,
            .sensorFailedDueToHighCountsAberration,
            .sensorFailedDueToLowCountsAberration,
            .sensorFailedDueToRestart
        ]
        for state in g7Failures {
            #expect(AlgorithmState.known(state).reportableStatus?.key == "sensorFailed", "\(state)")
        }
        for state in [AlgorithmState.State.calibrationError1, .calibrationError2, .calibrationLinearityFitFailure] {
            #expect(AlgorithmState.known(state).reportableStatus?.key == "calibrationError", "\(state)")
        }
        for state in [CalibrationState.State.sensorFailure11, .sensorFailure12] {
            #expect(CalibrationState.known(state).reportableStatus?.key == "sensorFailed", "\(state)")
        }
        for state in [CalibrationState.State.sessionFailure15, .sessionFailure16, .sessionFailure17] {
            #expect(CalibrationState.known(state).reportableStatus?.key == "sessionFailed", "\(state)")
        }
        for state in [CalibrationState.State.calibrationError8, .calibrationError13] {
            #expect(CalibrationState.known(state).reportableStatus?.key == "calibrationError", "\(state)")
        }
    }

    // MARK: - Note text

    /// Pins the wording: Nightscout exports are read long after the fact.
    @Test("Note carries a plain label plus the raw device state") func noteFormatIsStableAndDiagnosable() {
        let note = AlgorithmState.known(.temporarySensorIssue).reportableStatus?.note
        #expect(note == "CGM: Sensor issue (temporarySensorIssue)")
    }

    // MARK: - Unknown states

    /// Firmware can ship states this build has never seen; one must not mask
    /// another.
    @Test("Unknown raw values are reported with per-value dedup keys") func unknownStatesReportIndependently() {
        let first = AlgorithmState(rawValue: 99).reportableStatus
        let second = AlgorithmState(rawValue: 100).reportableStatus
        #expect(first?.key == "unrecognized.99")
        #expect(second?.key == "unrecognized.100")
        #expect(first?.note == "CGM: Unrecognized sensor state (raw value 99)")
        #expect(CalibrationState(rawValue: 99).reportableStatus?.key == "unrecognized.99")
    }

    // MARK: - Total coverage

    /// Pins the silent list across the whole `UInt8` space, so widening it is
    /// a deliberate edit here. (Fall-through is already a compile error: the
    /// mapping switches exhaustively.)
    @Test("Every representable raw value maps to a status or a known-silent state") func everyRawValueIsHandled() {
        let silentG7: Set<UInt8> = [
            AlgorithmState.State.ok.rawValue,
            AlgorithmState.State.warmup.rawValue,
            AlgorithmState.State.sessionEnded.rawValue,
            AlgorithmState.State.stopped.rawValue,
            AlgorithmState.State.needsCalibration.rawValue,
            AlgorithmState.State.firstOfTwoBGsNeeded.rawValue,
            AlgorithmState.State.secondOfTwoBGsNeeded.rawValue,
            AlgorithmState.State.outlierCalibrationRequest.rawValue
        ]
        for raw in UInt8.min ... UInt8.max {
            let status = AlgorithmState(rawValue: raw).reportableStatus
            if silentG7.contains(raw) {
                #expect(status == nil, "raw \(raw) should be silent")
            } else {
                #expect(status != nil, "raw \(raw) fell through unhandled")
            }
        }

        let silentG6: Set<UInt8> = [
            CalibrationState.State.ok.rawValue,
            CalibrationState.State.warmup.rawValue,
            CalibrationState.State.stopped.rawValue,
            CalibrationState.State.needCalibration7.rawValue,
            CalibrationState.State.needCalibration14.rawValue,
            CalibrationState.State.needFirstInitialCalibration.rawValue,
            CalibrationState.State.needSecondInitialCalibration.rawValue
        ]
        for raw in UInt8.min ... UInt8.max {
            let status = CalibrationState(rawValue: raw).reportableStatus
            if silentG6.contains(raw) {
                #expect(status == nil, "raw \(raw) should be silent")
            } else {
                #expect(status != nil, "raw \(raw) fell through unhandled")
            }
        }
    }
}

@Suite("CGM: sensor episode policy") struct CGMSensorEpisodesTests {
    let issue = AlgorithmState.known(.temporarySensorIssue).reportableStatus!
    let noise = AlgorithmState.known(.excessNoise).reportableStatus!
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let tenDays: TimeInterval = 10 * 24 * 60 * 60

    /// Drives the log the way `reportCGMSensorObservation` does.
    @discardableResult private func feed(
        _ log: inout CGMSensorEpisodes,
        _ observation: CGMSensorObservation,
        uploadSucceeds: Bool = true
    ) -> CGMSensorStatus? {
        guard let pending = log.observe(observation) else { return nil }
        if uploadSucceeds { log.markReported(pending) }
        return pending
    }

    @Test("A problem is reported once, then stays quiet however long it persists") func onePerEpisode() {
        var log = CGMSensorEpisodes()
        #expect(feed(&log, .problem(issue)) != nil)
        for step in 1 ... 144 {
            #expect(feed(&log, .problem(issue)) == nil, "re-reported at step \(step)")
        }
    }

    @Test("Alternating between two problems yields one note each, not one per switch") func alternatingProblemsReportOnce() {
        var log = CGMSensorEpisodes()
        var reports = 0
        for step in 0 ..< 60 {
            if feed(&log, .problem(step.isMultiple(of: 2) ? issue : noise)) != nil { reports += 1 }
        }
        #expect(reports == 2)
    }

    /// A healthy reading closes every open episode, not only the matching one.
    @Test("A healthy reading closes the episodes, so a returning problem reports again") func healthyReadingReArms() {
        var log = CGMSensorEpisodes()
        #expect(feed(&log, .problem(issue)) != nil)
        #expect(feed(&log, .problem(noise)) != nil)
        #expect(feed(&log, .problem(issue)) == nil)
        #expect(feed(&log, .healthy) == nil)
        #expect(feed(&log, .problem(issue)) != nil, "problem returning after recovery should report again")
        #expect(feed(&log, .problem(noise)) != nil)
    }

    /// Warmup, a stopped session and an unreadable manager all prove nothing,
    /// so they must not stand in for recovery.
    @Test("Indeterminate readings do not close an episode") func indeterminateDoesNotReArm() {
        var log = CGMSensorEpisodes()
        #expect(feed(&log, .problem(issue)) != nil)
        for step in 1 ... 20 {
            #expect(feed(&log, .indeterminate) == nil)
            #expect(feed(&log, .problem(issue)) == nil, "re-reported at step \(step)")
        }
    }

    /// The G7 states seen while a sensor is struggling but not faulting.
    @Test("Warmup, stopped and session-ended are indeterminate, not healthy") func nonHealthyStatesAreIndeterminate() {
        for state in [AlgorithmState.State.warmup, .stopped, .sessionEnded] {
            #expect(AlgorithmState.known(state).observation == .indeterminate, "\(state)")
        }
        #expect(AlgorithmState.known(.ok).observation == .healthy)
        #expect(AlgorithmState(rawValue: 99).observation != .healthy)
    }

    /// G5/G6 treat a routine calibration prompt as still-reliable glucose, but
    /// an uncalibrated new sensor has proven nothing.
    @Test("G6 calibration prompts are healthy, initial calibration is not") func g6CalibrationObservations() {
        for state in [CalibrationState.State.ok, .needCalibration7, .needCalibration14] {
            #expect(CalibrationState.known(state).observation == .healthy, "\(state)")
        }
        for state in [CalibrationState.State.needFirstInitialCalibration, .needSecondInitialCalibration, .warmup] {
            #expect(CalibrationState.known(state).observation == .indeterminate, "\(state)")
        }
    }

    @Test("A failed upload is retried on the next reading") func failedUploadRetries() {
        var log = CGMSensorEpisodes()
        #expect(feed(&log, .problem(issue), uploadSucceeds: false) != nil)
        #expect(feed(&log, .problem(issue), uploadSucceeds: true) != nil, "should retry after failure")
        #expect(feed(&log, .problem(issue)) == nil)
    }

    /// The replacement sensor fails the same way during warmup, before any
    /// reading can close the outgoing sensor's episode.
    @Test("A new session reports immediately, ignoring the previous session's episodes") func newSessionReArms() {
        var log = CGMSensorEpisodes()
        log.startSensor(startedAt: start)
        #expect(feed(&log, .problem(issue)) != nil)
        #expect(feed(&log, .problem(issue)) == nil)
        log.startSensor(startedAt: start.addingTimeInterval(tenDays))
        #expect(feed(&log, .indeterminate) == nil, "warmup must not close the episode")
        #expect(feed(&log, .problem(issue)) != nil, "new session should report")
    }

    /// A struggling sensor disconnects and is re-discovered mid-problem; that
    /// is the same session, so its episode must stay open.
    @Test("Re-discovering the same session keeps its episodes open") func sameSessionKeepsEpisodes() {
        var log = CGMSensorEpisodes()
        log.startSensor(startedAt: start)
        #expect(feed(&log, .problem(issue)) != nil)
        log.startSensor(startedAt: start)
        #expect(feed(&log, .problem(issue)) == nil, "same session should not re-arm")
    }

    @Test("The log round-trips through Codable so episodes survive a restart") func codableRoundTrip() throws {
        var log = CGMSensorEpisodes()
        log.startSensor(startedAt: start)
        feed(&log, .problem(issue))
        let decoded = try JSONDecoder().decode(
            CGMSensorEpisodes.self,
            from: JSONEncoder().encode(log)
        )
        #expect(decoded == log)
        var restored = decoded
        #expect(feed(&restored, .problem(issue)) == nil, "episode lost across restart")
    }
}
