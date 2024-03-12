//
//  LibreError.swift
//  MiaomiaoClient
//
//  Created by LoopKit Authors on 05/03/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

public enum LibreError: Error {
    case noSensorData
    case noCalibrationData
    case invalidCalibrationData
    case checksumValidationError
    case expiredSensor
    case invalidAutoCalibrationCredentials
    case encryptedSensor
    case noValidSensorData

    public var errorDescription: String {
        switch self {
        case .noSensorData:
            return "No sensor data present"
        case .noValidSensorData:
            return "No valid sensor data present, but sensor is running. Maybe due to sensor being off-body?"

        case .noCalibrationData:
            return "No calibration data present"
        case .invalidCalibrationData:
            return "invalid calibration data detected"
        case .checksumValidationError:
            return "Checksum Validation Error "
        case .expiredSensor:
            return "Sensor has expired"
        case .invalidAutoCalibrationCredentials:
            return "Invalid Auto Calibration Credentials"
        case .encryptedSensor:
            return "Encrypted or unsupported libre sensor detected."
        }
    }
}
