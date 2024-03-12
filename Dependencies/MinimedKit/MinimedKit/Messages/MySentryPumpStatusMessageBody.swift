//
//  MySentryPumpStatusMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/5/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum GlucoseTrend {
    case flat
    case up
    case upUp
    case down
    case downDown
    
    init?(byte: UInt8) {
        switch byte & 0b1110 {
        case 0b0000:
            self = .flat
        case 0b0010:
            self = .up
        case 0b0100:
            self = .upUp
        case 0b0110:
            self = .down
        case 0b1000:
            self = .downDown
        default:
            return nil
        }
    }
}


public enum SensorReading {
    case off
    case missing
    case meterBGNow
    case weakSignal
    case calError
    case warmup
    case ended
    case highBG  // Above 400 mg/dL
    case lost
    case unknown
    case active(glucose: Int)
    
    init(glucose: Int) {
        switch glucose {
        case 0:
            self = .off
        case 1:
            self = .missing
        case 2:
            self = .meterBGNow
        case 4:
            self = .weakSignal
        case 6:
            self = .calError
        case 8:
            self = .warmup
        case 10:
            self = .ended
        case 14:
            self = .highBG
        case 20:
            self = .lost
        case 0...20:
            self = .unknown
        default:
            self = .active(glucose: glucose)
        }
    }
}

public enum ClockType {
    case twentyFourHour
    case twelveHour
}


/**
 Describes a status message sent periodically from the pump to any paired MySentry devices
 
 See: [MinimedRF Class](https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/pump_status.rb)
 ```
 -- ------ -- 00 01 020304050607 08 09 10 11 1213 14 15 16 17 18 19 20 21 2223 24 25 26 27 282930313233 3435 --
              se tr    pump date 01 bh ph    resv bt          st sr nxcal  iob bl             sens date 0000
 a2 594040 04 c9 51 092c1e0f0904 01 32 33 00 037a 02 02 05 b0 18 30 13 2b 00d1 00 00 00 70 092b000f0904 0000 33
 a2 594040 04 fb 51 1205000f0906 01 05 05 02 0000 04 00 00 00 ff 00 ff ff 0040 00 00 00 71 1205000f0906 0000 2b
 a2 594040 04 ff 50 1219000f0906 01 00 00 00 0000 04 00 00 00 00 00 00 00 005e 00 00 00 72 000000000000 0000 8b
 a2 594040 04 01 50 1223000f0906 01 00 00 00 0000 04 00 00 00 00 00 00 00 0059 00 00 00 72 000000000000 0000 9f
 a2 594040 04 2f 51 1727070f0905 01 84 85 00 00cd 01 01 05 b0 3e 0a 0a 1a 009d 03 00 00 71 1726000f0905 0000 d0
 a2 594040 04 9c 51 0003310f0905 01 39 37 00 025b 01 01 06 8d 26 22 08 15 0034 00 00 00 70 0003000f0905 0000 67
 a2 594040 04 87 51 0f18150f0907 01 03 71 00 045e 04 02 07 2c 04 44 ff ff 005e 02 00 00 73 0f16000f0907 0000 35
 ```
 */
public struct MySentryPumpStatusMessageBody: DecodableMessageBody, MessageBody, DictionaryRepresentable {
    private static let reservoirMultiplier: Double = 10
    private static let iobMultiplier: Double = 40
    public static let length = 36

    public let sequence: UInt8

    public let pumpDateComponents: DateComponents
    public let batteryRemainingPercent: Int
    public let iob: Double
    public let reservoirRemainingUnits: Double
    public let reservoirRemainingPercent: Int
    public let reservoirRemainingMinutes: Int
    
    public let glucoseTrend: GlucoseTrend
    public let glucoseDateComponents: DateComponents?
    public let glucose: SensorReading
    public let previousGlucose: SensorReading
    public let sensorAgeHours: Int
    public let sensorRemainingHours: Int
    public let clockType: ClockType
    
    public let nextSensorCalibrationDateComponents: DateComponents?
    
    private let rxData: Data
    
    public init?(rxData: Data) {
        guard rxData.count == type(of: self).length, let trend = GlucoseTrend(byte: rxData[1]) else {
            return nil
        }
        
        self.rxData = rxData

        sequence = rxData[0]

        let pumpDateComponents = DateComponents(mySentryBytes: rxData.subdata(in: 2..<8))
        
        let hourByte: UInt8 = rxData[2]
        clockType = ((hourByte & 0b10000000) > 0) ? .twentyFourHour : .twelveHour
        
        guard let calendar = pumpDateComponents.calendar, pumpDateComponents.isValidDate(in: calendar) else {
            return nil
        }
        
        self.pumpDateComponents = pumpDateComponents
        
        self.glucoseTrend = trend
        
        reservoirRemainingUnits = Double(Int(bigEndianBytes: rxData.subdata(in: 12..<14))) / type(of: self).reservoirMultiplier
        
        let reservoirRemainingPercent: UInt8 = rxData[15]
        self.reservoirRemainingPercent = Int(round(Double(reservoirRemainingPercent) / 4.0 * 100))
        
        reservoirRemainingMinutes = Int(bigEndianBytes: rxData.subdata(in: 16..<18))
        
        iob = Double(Int(bigEndianBytes: rxData.subdata(in: 22..<24))) / type(of: self).iobMultiplier
        
        let batteryRemainingPercent: UInt8 = rxData[14]
        self.batteryRemainingPercent = Int(round(Double(batteryRemainingPercent) / 4.0 * 100))
        
        let glucoseValue = Int(bigEndianBytes: Data([rxData[9], rxData[24] << 7])) >> 7
        let previousGlucoseValue = Int(bigEndianBytes: Data([rxData[10], rxData[24] << 6])) >> 7
        
        glucose = SensorReading(glucose: glucoseValue)
        previousGlucose = SensorReading(glucose: previousGlucoseValue)
        
        switch glucose {
        case .off:
            glucoseDateComponents = nil
        default:
            let glucoseDateComponents = DateComponents(mySentryBytes: rxData.subdata(in: 28..<34))
            
            if glucoseDateComponents.isValidDate(in: calendar) {
                self.glucoseDateComponents = glucoseDateComponents
            } else {
                self.glucoseDateComponents = nil
            }
        }
        
        let sensorAgeHours: UInt8 = rxData[18]
        self.sensorAgeHours = Int(sensorAgeHours)
        
        let sensorRemainingHours: UInt8 = rxData[19]
        self.sensorRemainingHours = Int(sensorRemainingHours)
        
        let matchingHour: UInt8 = rxData[20]
        var nextSensorCalibrationDateComponents = DateComponents()
        nextSensorCalibrationDateComponents.hour = Int(matchingHour)
        nextSensorCalibrationDateComponents.minute = Int(rxData[21])
        nextSensorCalibrationDateComponents.calendar = calendar
        self.nextSensorCalibrationDateComponents = nextSensorCalibrationDateComponents
    }
    
    public var dictionaryRepresentation: [String: Any] {
        let dateComponentsString = { (components: DateComponents) -> String in
            String(
                format: "%04d-%02d-%02dT%02d:%02d:%02d",
                components.year!,
                components.month!,
                components.day!,
                components.hour!,
                components.minute!,
                components.second!
            )
        }
        
        var dict: [String: Any] = [
            "glucoseTrend": String(describing: glucoseTrend),
            "pumpDate": dateComponentsString(pumpDateComponents),
            "reservoirRemaining": reservoirRemainingUnits,
            "reservoirRemainingPercent": reservoirRemainingPercent,
            "reservoirRemainingMinutes": reservoirRemainingMinutes,
            "iob": iob
        ]
        
        switch glucose {
        case .active(glucose: let glucose):
            dict["glucose"] = glucose
        default:
            break
        }
        
        if let glucoseDateComponents = glucoseDateComponents {
            dict["glucoseDate"] = dateComponentsString(glucoseDateComponents)
        }
        dict["sensorStatus"] = String(describing: glucose)
        
        switch previousGlucose {
        case .active(glucose: let glucose):
            dict["lastGlucose"] = glucose
        default:
            break
        }
        dict["lastSensorStatus"] = String(describing: previousGlucose)
        
        dict["sensorAgeHours"] = sensorAgeHours
        dict["sensorRemainingHours"] = sensorRemainingHours
        if let components = nextSensorCalibrationDateComponents {
            dict["nextSensorCalibration"] = String(format: "%02d:%02d", components.hour!, components.minute!)
        }
        
        dict["batteryRemainingPercent"] = batteryRemainingPercent
        
        dict["byte1"] = rxData.subdata(in: 1..<2).hexadecimalString
        // {50}
        let byte1: UInt8 = rxData[1]
        dict["byte1High"] = String(format: "%02x", byte1 & 0b11110000)
        // {1}
        dict["byte1Low"] = Int(byte1 & 0b00000001)
        // Observed values: 00, 01, 02, 03
        // These seem to correspond with carb/bolus activity
        dict["byte11"] = rxData.subdata(in: 11..<12).hexadecimalString
        // Current alarms?
        // 25: {00,52,65} 4:49 AM - 4:59 AM
        // 26: 00
        dict["byte2526"] = rxData.subdata(in: 25..<27).hexadecimalString
        // 27: {73}
        dict["byte27"] = rxData.subdata(in: 27..<28).hexadecimalString
        
        return dict
    }
    
    public var txData: Data {
        return rxData
    }

    public var description: String {
        return "MySentryPumpStatus(seq:\(sequence), pumpDate:\(pumpDateComponents), batt:\(batteryRemainingPercent), iob:\(iob), reservoir:\(reservoirRemainingUnits), reservoir_percent:\(reservoirRemainingPercent), reservoir_minutes:\(reservoirRemainingMinutes), glucose_trend:\(glucoseTrend), glucose_date:\(String(describing: glucoseDateComponents)), glucose:\(glucose), previous_glucose:\(previousGlucose), sensor_age:\(sensorAgeHours), sensor_remaining:\(sensorRemainingHours), clock_type:\(clockType), next_cal:\(String(describing: nextSensorCalibrationDateComponents)))"
    }
}

extension MySentryPumpStatusMessageBody: Equatable {
}

public func ==(lhs: MySentryPumpStatusMessageBody, rhs: MySentryPumpStatusMessageBody) -> Bool {
    return lhs.pumpDateComponents == rhs.pumpDateComponents && lhs.glucoseDateComponents == rhs.glucoseDateComponents
}
