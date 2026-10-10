import CGMBLEKit
import Foundation
import G7SensorKit

/// What a single reading says about the sensor.
enum CGMSensorObservation: Equatable {
    case reliable
    case unreliable(state: String)
    /// No reading, or a manager Trio cannot read. Leaves the log untouched.
    case unavailable
}

extension AlgorithmState {
    var observation: CGMSensorObservation {
        hasReliableGlucose ? .reliable : .unreliable(state: description)
    }
}

extension CalibrationState {
    var observation: CGMSensorObservation {
        hasReliableGlucose ? .reliable : .unreliable(state: description)
    }
}

/// Decides which sensor states become Nightscout notes: a state without
/// reliable glucose is noted once, and a reliable reading re-arms the log so
/// a returning state is noted again.
struct CGMSensorStateLog: Codable, Equatable {
    /// State whose note is uploading or has reached Nightscout.
    private(set) var notedState: String?
    private(set) var sensorSessionStart: Date?

    /// Returns the state to note, or nil. Call `uploadFailed` if its upload
    /// does not succeed.
    mutating func observe(_ observation: CGMSensorObservation) -> String? {
        switch observation {
        case .reliable:
            notedState = nil
            return nil
        case .unavailable:
            return nil
        case let .unreliable(state):
            guard state != notedState else { return nil }
            notedState = state
            return state
        }
    }

    /// Re-arms `state` so the next reading retries its note.
    mutating func uploadFailed(_ state: String) {
        if notedState == state { notedState = nil }
    }

    /// Re-discovering the session already tracked keeps the log.
    mutating func startSensor(startedAt: Date) {
        guard startedAt != sensorSessionStart else { return }
        sensorSessionStart = startedAt
        notedState = nil
    }
}
