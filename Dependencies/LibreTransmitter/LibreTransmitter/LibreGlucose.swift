//
//  MiaomiaoClient.h
//  MiaomiaoClient
//

import Foundation
import HealthKit
import LoopKit
import os.log

private var logger = Logger(forType: "LibreGlucose")

public struct LibreGlucose: Codable, Hashable {
    public let unsmoothedGlucose: Double
    public var glucoseDouble: Double
    public var error = [MeasurementError.OK]
    public var glucose: UInt16 {
        UInt16(glucoseDouble.rounded())
    }

    public var timestamp: Date

    public init(unsmoothedGlucose: Double, glucoseDouble: Double, error: [MeasurementError] = [MeasurementError.OK], timestamp: Date) {
        self.unsmoothedGlucose = unsmoothedGlucose
        self.glucoseDouble = glucoseDouble
        self.timestamp = timestamp
    }

    public static func timeDifference(oldGlucose: LibreGlucose, newGlucose: LibreGlucose) -> TimeInterval {
        newGlucose.startDate.timeIntervalSince(oldGlucose.startDate)
    }

    public var syncId: String {
        "\(Int(self.startDate.timeIntervalSince1970))\(self.unsmoothedGlucose)"
    }

    public var isStateValid: Bool {
        // We know that the official libre algorithm doesn't produce values
        // below 39. However, both the raw sensor contents and the derived algorithm
        // supports values down to 0 without issues. A bit uncertain if nightscout and loop will work with values below 1, so we restrict this to 1
        glucose >= 1
    }

    public func GetGlucoseTrend(last: Self) -> GlucoseTrend {
        Self.GetGlucoseTrend(current: self, last: last)
    }
}

extension LibreGlucose: GlucoseValue {
    public var startDate: Date {
        timestamp
    }

    public var quantity: HKQuantity {
        .init(unit: .milligramsPerDeciliter, doubleValue: glucoseDouble)
    }
}

extension LibreGlucose {
    static func calculateSlope(current: Self, last: Self) -> Double {
        if current.timestamp == last.timestamp {
            return 0.0
        }

        let _curr = Double(current.timestamp.timeIntervalSince1970 * 1_000)
        let _last = Double(last.timestamp.timeIntervalSince1970 * 1_000)

        return (Double(last.unsmoothedGlucose) - Double(current.unsmoothedGlucose)) / (_last - _curr)
    }

    static func calculateSlopeByMinute(current: Self, last: Self) -> Double {
        return calculateSlope(current: current, last: last) * 60_000
    }

    static func GetGlucoseTrend(current: Self?, last: Self?) -> GlucoseTrend {

        guard let current, let last else {
            return  .flat
        }

        let  s = calculateSlopeByMinute(current: current, last: last)

        switch s {
        case _ where s <= (-3.5):
            return .downDownDown
        case _ where s <= (-2):
            return .downDown
        case _ where s <= (-1):
            return .down
        case _ where s <= (1):
            return .flat
        case _ where s <= (2):
            return .up
        case _ where s <= (3.5):
            return .upUp
        case _ where s <= (40):
            return .flat // flat is the new (tm) "unknown"!

        default:

            return .flat
        }
    }
}

extension LibreGlucose {
    static func fromHistoryMeasurements(_ measurements: [Measurement], nativeCalibrationData: SensorData.CalibrationInfo) -> [LibreGlucose] {
        var arr = [LibreGlucose]()

        for historical in measurements {
            let calibrated = historical.calibratedGlucose(calibrationInfo: nativeCalibrationData)
            let glucose = LibreGlucose(
                // unsmoothedGlucose: historical.temperatureAlgorithmGlucose,
                // glucoseDouble: historical.temperatureAlgorithmGlucose,
                unsmoothedGlucose: calibrated,
                glucoseDouble: calibrated,
                error: historical.error,
                timestamp: historical.date)

            if glucose.glucoseDouble > 0 {
                arr.append(glucose)
            }
        }

        return arr
    }

    static func fromTrendMeasurements(_ measurements: [Measurement], nativeCalibrationData: SensorData.CalibrationInfo) -> [LibreGlucose] {
        var arr = [LibreGlucose]()

        var shouldSmoothGlucose = true
        for trend in measurements {
            // trend arrows on each libreglucose value is not needed
            // instead we calculate it once when latestbackfill is set, which in turn sets
            // the sensordisplayable property
            let glucose = LibreGlucose(
                // unsmoothedGlucose: trend.temperatureAlgorithmGlucose,
                unsmoothedGlucose: trend.calibratedGlucose(calibrationInfo: nativeCalibrationData),
                glucoseDouble: 0.0,
                error: trend.error,
                timestamp: trend.date)
            // if sensor is ripped off body while transmitter is attached, values below 1 might be created
            // libre manual: glucose readings are gathered in the system range of 40-500 mg/dL
            if glucose.unsmoothedGlucose > 0 && glucose.unsmoothedGlucose <= 500 {
                arr.append(glucose)
            }

            // Just for expliciticity, if one of the values are 0,
            // then the rest of the values should not be smoothed
            if glucose.unsmoothedGlucose <= 0 {
                shouldSmoothGlucose = false
            }
        }

        if shouldSmoothGlucose {
            arr = CalculateSmothedData5Points(origtrends: arr)
        } else {
            for i in 0 ..< arr.count {
                arr[i].glucoseDouble = arr[i].unsmoothedGlucose
            }
        }

        return arr
    }
}
