import CGMBLEKit
import Foundation
import G7SensorKit

/// An abnormal CGM sensor state, carrying the raw device state it came from.
///
/// Derived from the manager's `latestReading`.
enum CGMSensorStatus: Equatable {
    case sensorIssue(String)
    case sensorFailed(String)
    case sessionFailed(String)
    case sensorExpired(String)
    case excessNoise(String)
    case calibrationError(String)
    case unrecognized(rawValue: UInt8)

    /// Identifies the kind of problem for de-duplication. Coarser than the raw
    /// device state, so drifting between flavours of one failure stays quiet.
    var key: String {
        switch self {
        case .sensorIssue: "sensorIssue"
        case .sensorFailed: "sensorFailed"
        case .sessionFailed: "sessionFailed"
        case .sensorExpired: "sensorExpired"
        case .excessNoise: "excessNoise"
        case .calibrationError: "calibrationError"
        case let .unrecognized(rawValue): "unrecognized.\(rawValue)"
        }
    }

    /// Note body uploaded to Nightscout. Not localized: a historical record
    /// stays readable in aggregate only if its wording is fixed.
    var note: String {
        switch self {
        case let .sensorIssue(raw): "CGM: Sensor issue (\(raw))"
        case let .sensorFailed(raw): "CGM: Sensor failed (\(raw))"
        case let .sessionFailed(raw): "CGM: Sensor session failed (\(raw))"
        case let .sensorExpired(raw): "CGM: Sensor expired (\(raw))"
        case let .excessNoise(raw): "CGM: Excess noise (\(raw))"
        case let .calibrationError(raw): "CGM: Sensor calibration error (\(raw))"
        case let .unrecognized(rawValue): "CGM: Unrecognized sensor state (raw value \(rawValue))"
        }
    }
}

// MARK: - Reporting policy

/// What a single reading says about the sensor.
enum CGMSensorObservation: Equatable {
    /// The sensor produced glucose its own kit considers reliable.
    case healthy
    /// A fault worth recording.
    case problem(CGMSensorStatus)
    /// Neither: warming up, stopped, session ended, awaiting first
    /// calibration, or a manager whose state Trio cannot read. Absence of a
    /// fault is not recovery, so this leaves open episodes untouched.
    case indeterminate
}

/// Decides which observed sensor states become Nightscout notes.
///
/// One note per episode: a problem is reported when it starts and stays quiet
/// while it persists. A healthy reading closes the open episodes, so a problem
/// that clears and returns is reported again.
struct CGMSensorEpisodes: Codable, Equatable {
    /// Reported problems whose episode is still open, keyed by kind so a
    /// sensor alternating between two faults reports each once.
    private(set) var openEpisodes: Set<String> = []

    /// Start of the sensor session those episodes belong to.
    private(set) var sensorSessionStart: Date?

    init() {}

    /// Returns the status to upload, if any.
    ///
    /// Does not mark it reported: call `markReported` once the upload
    /// succeeds, so a failed upload is retried on the next reading.
    mutating func observe(_ observation: CGMSensorObservation) -> CGMSensorStatus? {
        switch observation {
        case .healthy:
            openEpisodes.removeAll()
            return nil
        case .indeterminate:
            return nil
        case let .problem(status):
            return openEpisodes.contains(status.key) ? nil : status
        }
    }

    /// Opens the episode for `status`, silencing it until the sensor recovers.
    mutating func markReported(_ status: CGMSensorStatus) {
        openEpisodes.insert(status.key)
    }

    /// Starts fresh for a new sensor session. Re-discovering the session
    /// already being tracked leaves its episodes open, so a sensor that
    /// disconnects and reconnects mid-problem does not re-report.
    mutating func startSensor(startedAt: Date) {
        guard startedAt != sensorSessionStart else { return }
        sensorSessionStart = startedAt
        openEpisodes.removeAll()
    }
}

// MARK: - Dexcom G7

extension AlgorithmState {
    /// Recovery is proven by a reading the kit itself calls reliable, never by
    /// the mere absence of a fault.
    var observation: CGMSensorObservation {
        if let status = reportableStatus { return .problem(status) }
        return hasReliableGlucose ? .healthy : .indeterminate
    }

    /// The reportable status for this G7 state, or `nil` for normal operation:
    /// the healthy state, lifecycle steps (`stopped` is usually the user
    /// ending a session), and routine calibration requests.
    var reportableStatus: CGMSensorStatus? {
        switch self {
        case let .unknown(rawValue):
            return .unrecognized(rawValue: rawValue)
        case let .known(state):
            let raw = String(describing: state)
            switch state {
            case .firstOfTwoBGsNeeded,
                 .needsCalibration,
                 .ok,
                 .outlierCalibrationRequest,
                 .secondOfTwoBGsNeeded,
                 .sessionEnded,
                 .stopped,
                 .warmup:
                return nil
            case .temporarySensorIssue:
                return .sensorIssue(raw)
            case .sensorFailed,
                 .sensorFailedDuetoCountsAberration,
                 .sensorFailedDueToHighCountsAberration,
                 .sensorFailedDueToLowCountsAberration,
                 .sensorFailedDueToProgressiveSensorDecline,
                 .sensorFailedDuetoResidualAberration,
                 .sensorFailedDueToRestart:
                return .sensorFailed(raw)
            case .sessionFailedDueToTransmitterError,
                 .sessionFailedDueToUnrecoverableError:
                return .sessionFailed(raw)
            case .expired,
                 .sessionExpired:
                return .sensorExpired(raw)
            case .excessNoise:
                return .excessNoise(raw)
            case .calibrationError1,
                 .calibrationError2,
                 .calibrationLinearityFitFailure,
                 .outOfCalibrationDueToOutlier:
                return .calibrationError(raw)
            }
        }
    }
}

// MARK: - Dexcom G5 / G6

extension CalibrationState {
    var observation: CGMSensorObservation {
        if let status = reportableStatus { return .problem(status) }
        return hasReliableGlucose ? .healthy : .indeterminate
    }

    /// The reportable status for this G5/G6 state, or `nil` for normal
    /// operation, which here includes the routine calibration prompts these
    /// user-calibrated sensors raise. Calibration *errors* are reported.
    ///
    /// `questionMarks` is the state behind the receiver's "???", the G6
    /// analogue of G7's `temporarySensorIssue`.
    var reportableStatus: CGMSensorStatus? {
        switch self {
        case let .unknown(rawValue):
            return .unrecognized(rawValue: rawValue)
        case let .known(state):
            let raw = String(describing: state)
            switch state {
            case .needCalibration7,
                 .needCalibration14,
                 .needFirstInitialCalibration,
                 .needSecondInitialCalibration,
                 .ok,
                 .stopped,
                 .warmup:
                return nil
            case .questionMarks:
                return .sensorIssue(raw)
            case .sensorFailure11,
                 .sensorFailure12:
                return .sensorFailed(raw)
            case .sessionFailure15,
                 .sessionFailure16,
                 .sessionFailure17:
                return .sessionFailed(raw)
            case .calibrationError8,
                 .calibrationError9,
                 .calibrationError10,
                 .calibrationError13:
                return .calibrationError(raw)
            }
        }
    }
}
