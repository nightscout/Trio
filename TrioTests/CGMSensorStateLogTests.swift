import CGMBLEKit
import Foundation
import G7SensorKit
import Testing

@testable import Trio

@Suite("CGM: sensor state observation") struct CGMSensorStateObservationTests {
    @Test("A reading is reliable or carries the kit's name for its state") func observationFollowsTheKit() {
        #expect(AlgorithmState.known(.ok).observation == .reliable)
        #expect(AlgorithmState.known(.temporarySensorIssue).observation == .unreliable(state: "temporarySensorIssue"))
        #expect(AlgorithmState(rawValue: 99).observation == .unreliable(state: ".unknown(99)"))
        #expect(CalibrationState.known(.needCalibration7).observation == .reliable)
        #expect(CalibrationState.known(.questionMarks).observation == .unreliable(state: "questionMarks"))
    }
}

@Suite("CGM: sensor state log") struct CGMSensorStateLogTests {
    let issue = CGMSensorObservation.unreliable(state: "temporarySensorIssue")
    let noise = CGMSensorObservation.unreliable(state: "excessNoise")
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A state is noted once") func onePerState() {
        var log = CGMSensorStateLog()
        #expect(log.observe(issue) == "temporarySensorIssue")
        #expect(log.observe(issue) == nil)
        #expect(log.observe(issue) == nil)
    }

    @Test("A change of state is noted, including a return to an earlier state") func stateChangesAreNoted() {
        var log = CGMSensorStateLog()
        #expect(log.observe(issue) == "temporarySensorIssue")
        #expect(log.observe(noise) == "excessNoise")
        #expect(log.observe(noise) == nil)
        #expect(log.observe(issue) == "temporarySensorIssue")
    }

    @Test("A reliable reading re-arms the log") func reliableReadingReArms() {
        var log = CGMSensorStateLog()
        #expect(log.observe(issue) != nil)
        #expect(log.observe(.reliable) == nil)
        #expect(log.observe(issue) != nil)
    }

    @Test("An unavailable reading does not re-arm the log") func unavailableDoesNotReArm() {
        var log = CGMSensorStateLog()
        #expect(log.observe(issue) != nil)
        #expect(log.observe(.unavailable) == nil)
        #expect(log.observe(issue) == nil)
    }

    @Test("A failed upload is retried on the next reading") func failedUploadRetries() throws {
        var log = CGMSensorStateLog()
        let observed = log.observe(issue)
        let state = try #require(observed)
        log.uploadFailed(state)
        #expect(log.observe(issue) == state)
        #expect(log.observe(issue) == nil)
    }

    @Test("A failure landing after a change of state does not re-arm the new state") func staleFailureIsIgnored() throws {
        var log = CGMSensorStateLog()
        let observed = log.observe(issue)
        let stale = try #require(observed)
        #expect(log.observe(noise) != nil)
        log.uploadFailed(stale)
        #expect(log.observe(noise) == nil)
    }

    @Test("A new session re-arms the log, re-discovering the same session does not") func sessionsReArm() {
        var log = CGMSensorStateLog()
        log.startSensor(startedAt: start)
        #expect(log.observe(issue) != nil)
        log.startSensor(startedAt: start)
        #expect(log.observe(issue) == nil)
        log.startSensor(startedAt: start.addingTimeInterval(24 * 60 * 60))
        #expect(log.observe(issue) != nil)
    }

    @Test("The log round-trips through Codable") func codableRoundTrip() throws {
        var log = CGMSensorStateLog()
        log.startSensor(startedAt: start)
        _ = log.observe(issue)
        let decoded = try JSONDecoder().decode(CGMSensorStateLog.self, from: JSONEncoder().encode(log))
        #expect(decoded == log)
    }
}

/// Feeds transmitter messages through the real `G7CGMManager`, the way
/// `PluginSource.currentSensorObservation` reads them.
@Suite("CGM: sensor state from a G7 transmitter message") struct G7SensorStateInjectionTests {
    /// A G7 glucose message (138 mg/dL, state ok). Byte 14 is the algorithm
    /// state; bytes 12 and 13 are the glucose, 0xffff when the sensor has none.
    private func manager(state: UInt8, glucose: Bool = true) -> G7CGMManager? {
        var message: [UInt8] = [
            0x4E, 0x00, 0xC3, 0x55, 0x01, 0x00, 0x26, 0x01, 0x00, 0x01,
            0x06, 0x00, 0x8A, 0x00, 0x06, 0x01, 0x87, 0x00, 0x0F
        ]
        message[14] = state
        if !glucose {
            message[12] = 0xFF
            message[13] = 0xFF
        }
        return G7CGMManager(rawState: ["latestReading": Data(message)])
    }

    @Test("A healthy reading is reliable") func healthyReading() {
        #expect(manager(state: AlgorithmState.State.ok.rawValue)?.latestReading?.algorithmState.observation == .reliable)
    }

    @Test("A failed sensor without glucose carries the kit's state name") func failedSensor() {
        let observation = manager(state: AlgorithmState.State.sensorFailed.rawValue, glucose: false)?
            .latestReading?.algorithmState.observation
        #expect(observation == .unreliable(state: "sensorFailed"))
    }

    @Test("A state this build does not know carries its raw value") func unknownState() {
        #expect(manager(state: 99)?.latestReading?.algorithmState.observation == .unreliable(state: ".unknown(99)"))
    }
}
