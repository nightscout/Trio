//
//  Measurement.swift
//  LibreMonitor
//
//  Created by Uwe Petersen on 25.08.16.
//  Copyright © 2016 Uwe Petersen. All rights reserved.
//

import Foundation

protocol MeasurementProtocol {
    var rawGlucose: Int { get }
    /// The raw temperature as read from the sensor
    var rawTemperature: Int { get }

    var rawTemperatureAdjustment: Int { get }

    var error: [MeasurementError] { get}
}

extension MeasurementProtocol {
    func calibratedGlucose(calibrationInfo: SensorData.CalibrationInfo) -> Double {
        // add extraslope and extraoffset as indicated by user in the ui
        round(glucoseValueFromRaw(calibrationInfo: calibrationInfo)) * calibrationInfo.extraSlope + calibrationInfo.extraOffset
    }
}

public enum MeasurementError: Int, CaseIterable, Codable {
    case OK = 0
    case SD14_FIFO_OVERFLOW      = 1
    case FILTER_DELTA            = 0x02
    case WORK_VOLTAGE            = 0x04
    case PEAK_DELTA_EXCEEDED     = 0x08
    case AVG_DELTA_EXCEEDED      = 0x10
    case RF                      = 0x20
    case REF_R                   = 0x40
    case SIGNAL_SATURATED        = 128    //   0x80
    case SENSOR_SIGNAL_LOW       = 256    //  0x100
    case THERMISTOR_OUT_OF_RANGE = 2048   //  0x800

    case TEMP_HIGH               = 8192   // 0x2000
    case TEMP_LOW                = 16384  // 0x4000
    case INVALID_DATA            = 32768  // 0x8000

    static var allErrorCodes: [MeasurementError] {
        var allErrorCases = MeasurementError.allCases
        allErrorCases.removeAll { $0 == .OK}
        return allErrorCases
    }
}

/// Structure for one glucose measurement including value, date and raw data bytes
public struct Measurement: MeasurementProtocol, Codable, Hashable {
    /// The date for this measurement
    let date: Date
    /// The minute counter for this measurement
    let counter: Int
    /// The bytes as read from the sensor. All data is derived from this \"raw data"
    let bytes: [UInt8]
    /// The bytes as String
    let byteString: String
    /// The raw glucose as read from the sensor
    let rawGlucose: Int
    /// The raw temperature as read from the sensor
    let rawTemperature: Int

    let rawTemperatureAdjustment: Int

    let error: [MeasurementError]

    let idValue: Int

    init(date: Date, rawGlucose: Int, rawTemperature: Int, rawTemperatureAdjustment: Int, idValue: Int = 0) {
        self.date = date
        self.rawGlucose = rawGlucose
        self.rawTemperature = rawTemperature
        self.rawTemperatureAdjustment = rawTemperatureAdjustment

        // not really needed when setting the other properties above explicitly
        self.bytes = []
        self.byteString = ""
        self.error = [MeasurementError.OK]
        self.counter = 0

        // only used for sorting purposes
        self.idValue = idValue

    }

    ///
    /// - parameter bytes:  raw data bytes as read from the sensor
    /// - parameter slope:  slope to calculate glucose from raw value in (mg/dl)/raw
    /// - parameter offset: glucose offset to be added in mg/dl
    /// - parameter date:   date of the measurement
    ///
    /// - returns: Measurement
    init(bytes: [UInt8], slope: Double = 0.1, offset: Double = 0.0, counter: Int = 0, date: Date, idValue: Int = 0) {
        self.bytes = bytes
        self.byteString = bytes.reduce("", { $0 + String(format: "%02X", arguments: [$1]) })
        // self.rawGlucose = (Int(bytes[1] & 0x1F) << 8) + Int(bytes[0]) // switched to 13 bit mask on 2018-03-15
        self.rawGlucose = SensorData.readBits(bytes, 0, 0, 0xe)

        // self.rawTemperature = (Int(bytes[4] & 0x3F) << 8) + Int(bytes[3]) // 14 bit-mask for raw temperature
        // raw temperature in libre FRAM is always stored in multiples of four
        self.rawTemperature = SensorData.readBits(bytes, 0, 0x1a, 0xc) << 2

        let temperatureAdjustment = (SensorData.readBits(bytes, 0, 0x26, 0x9) << 2)
        let negativeAdjustment = SensorData.readBits(bytes, 0, 0x2f, 0x1) != 0
        self.rawTemperatureAdjustment = negativeAdjustment ? -temperatureAdjustment : temperatureAdjustment

        self.date = date
        self.counter = counter

        let errorBitField = SensorData.readBits(bytes, 0, 0xe, 0xc)
        self.error = Self.extractErrorBitField(errorBitField)

        // only used for sorting purposes
        self.idValue = idValue

    }

    static func extractErrorBitField(_ errBitField: Int) -> [MeasurementError] {
        errBitField == 0 ?
            [MeasurementError.OK] :
            MeasurementError.allErrorCodes.filter { (errBitField & $0.rawValue) != 0}

    }

    var description: String {
        String(" date:  \(date), rawGlucose: \(rawGlucose), rawTemperature: \(rawTemperature), bytes: \(bytes) \n")

    }
}
