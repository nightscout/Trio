public extension UserDefaults {
    private enum Key: String {
        case sensor = "com.loopkit.libre2sensor"
        case calibrationMapping = "com.loopkit.libre2sensor-calibrationmapping"
        case currentSensorUid = "com.loopkit.libre2sensor-currentSensorUid"

    }
    
    var currentSensor: String? {
        get {
            string(forKey: Key.currentSensorUid.rawValue)
        }
        
        set {
            if let newValue {
                set(newValue, forKey: Key.currentSensorUid.rawValue)
            }
            else {
                removeObject(forKey: Key.currentSensorUid.rawValue)
            }
        }
    }

    var preSelectedSensor: Sensor? {
        get {

            if let sensor = object(forKey: Key.sensor.rawValue) as? Data {
                let decoder = JSONDecoder()
                return try? decoder.decode(Sensor.self, from: sensor)
            }

            return nil

        }
        set {
            if let newValue {
                let encoder = JSONEncoder()
                if let encoded = try? encoder.encode(newValue) {
                    set(encoded, forKey: Key.sensor.rawValue)
                }
            } else {
                removeObject(forKey: Key.sensor.rawValue)
            }
        }
    }

    var calibrationMapping: CalibrationToSensorMapping? {
        get {
            if let sensor = object(forKey: Key.calibrationMapping.rawValue) as? Data {
                let decoder = JSONDecoder()
                return try? decoder.decode(CalibrationToSensorMapping.self, from: sensor)
            }

            return nil

        }
        set {
            if let newValue {
                let encoder = JSONEncoder()
                if let encoded = try? encoder.encode(newValue) {
                    set(encoded, forKey: Key.calibrationMapping.rawValue)
                }
            } else {
                removeObject(forKey: Key.calibrationMapping.rawValue)
            }
        }
    }
}

public struct CalibrationToSensorMapping: Codable {
    public let uuid: Data
    public let reverseFooterCRC: Int

    public init(uuid: Data, reverseFooterCRC: Int) {
        self.uuid = uuid
        self.reverseFooterCRC = reverseFooterCRC
    }
}

public struct Sensor: Codable {
    public let uuid: Data
    public let patchInfo: Data
   // public let calibrationInfo: SensorData.CalibrationInfo

    // public let family: SensorFamily
    // public let type: SensorType
    // public let region: SensorRegion
    // public let serial: String?
    // public var state: SensorState
    public var age: Int?
    public var maxAge: Int
   // public var lifetime: Int

    public var unlockCount: Int
    
    var sensorName : String?

    /*
    public var unlockCount: Int {
        get {
            return UserDefaults.standard.integer(forKey: Key.sensorUnlockCount.rawValue)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Key.sensorUnlockCount.rawValue)
        }
    }*/

    /*
    public var elapsedLifetime: Int? {
        get {
            if let remainingLifetime {
                return max(0, lifetime - remainingLifetime)
            }

            return nil
        }
    }

    public var remainingLifetime: Int? {
        get {
            if let age {
                return max(0, lifetime - age)
            }

            return nil
        }
    } */

    public init(uuid: Data, patchInfo: Data, maxAge: Int, unlockCount: Int = 0, sensorName: String? = nil) {
        self.uuid = uuid
        self.patchInfo = patchInfo

        // self.family = SensorFamily(patchInfo: patchInfo)
        // self.type = SensorType(patchInfo: patchInfo)
        // self.region = SensorRegion(patchInfo: patchInfo)
        // self.serial = sensorSerialNumber(sensorUID: self.uuid, sensorFamily: self.family)
        // self.state = SensorState(fram: fram)
        // self.lifetime = Int(fram[327]) << 8 + Int(fram[326])
        self.unlockCount = 0
        self.maxAge = maxAge
        // self.calibrationInfo = calibrationInfo
        self.sensorName = sensorName
    }

    public var description: String {
        return [
            "uuid: (\(uuid.hex))",
            "patchInfo: (\(patchInfo.hex))"
            // "calibrationInfo: (\(calibrationInfo.description))",
            // "family: \(family.description)",
            // "type: \(type.description)",
            // "region: \(region.description)",
            // "serial: \(serial ?? "Unknown")",
            // "state: \(state.description)",
            // "lifetime: \(lifetime.inTime)",
        ].joined(separator: ", ")
    }
}

private enum Key: String, CaseIterable {
    case sensorUnlockCount = "libre-direct.settings.sensor.unlockCount"
}
