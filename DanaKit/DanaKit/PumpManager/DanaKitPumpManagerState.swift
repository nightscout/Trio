import LoopKit

public enum DanaKitBasal: Int {
    case active = 0
    case suspended = 1
    case tempBasal = 2
}

public enum BolusState: Int {
    case noBolus = 0
    case initiating = 1
    case inProgress = 2
    case canceling = 3
}

public struct DanaKitPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = PumpManager.RawStateValue

    public init(rawValue: RawValue) {
        lastStatusDate = rawValue["lastStatusDate"] as? Date ?? Date().addingTimeInterval(.hours(-8))
        lastStatusPumpDateTime = rawValue["lastStatusPumpDateTime"] as? Date ?? lastStatusDate
        isUsingContinuousMode = rawValue["isUsingContinuousMode"] as? Bool ?? false
        deviceName = rawValue["deviceName"] as? String
        bleIdentifier = rawValue["bleIdentifier"] as? String
        isConnected = false // To prevent having an old isConnected state
        reservoirLevel = rawValue["reservoirLevel"] as? Double ?? 0
        hwModel = rawValue["hwModel"] as? UInt8 ?? 0
        pumpProtocol = rawValue["pumpProtocol"] as? UInt8 ?? 0
        encryptionMode = rawValue["encryptionMode"] as? UInt8 ?? DanaKitPumpManagerState.getEncryptionMode(hwModel)
        isInFetchHistoryMode = rawValue["isInFetchHistoryMode"] != nil
        ignorePassword = rawValue["ignorePassword"] as? Bool ?? false
        devicePassword = rawValue["devicePassword"] as? UInt16 ?? 0
        isOnBoarded = rawValue["isOnBoarded"] as? Bool ?? false
        basalDeliveryDate = rawValue["basalDeliveryDate"] as? Date ?? Date.now
        pumpTime = rawValue["pumpTime"] as? Date
        pumpTimeSyncedAt = rawValue["pumpTimeSyncedAt"] as? Date
        basalSchedule = rawValue["basalSchedule"] as? [Double] ?? []
        tempBasalUnits = rawValue["tempBasalUnits"] as? Double
        tempBasalDuration = rawValue["tempBasalDuration"] as? Double
        ble5Keys = rawValue["ble5Keys"] as? Data ?? Data([0, 0, 0, 0, 0, 0])
        pairingKey = rawValue["pairingKey"] as? Data ?? Data([0, 0, 0, 0, 0, 0])
        randomPairingKey = rawValue["randomPairingKey"] as? Data ?? Data([0, 0, 0])
        randomSyncKey = rawValue["randomSyncKey"] as? UInt8 ?? 0
        isTimeDisplay24H = rawValue["isTimeDisplay24H"] as? Bool ?? false
        isButtonScrollOnOff = rawValue["isButtonScrollOnOff"] as? Bool ?? false
        lcdOnTimeInSec = rawValue["lcdOnTimeInSec"] as? UInt8 ?? 0
        backlightOnTimInSec = rawValue["backlightOnTimInSec"] as? UInt8 ?? 0
        units = rawValue["units"] as? UInt8 ?? 0
        lowReservoirRate = rawValue["lowReservoirRate"] as? UInt8 ?? 0
        selectedLanguage = rawValue["selectedLanguage"] as? UInt8 ?? 0
        shutdownHour = rawValue["shutdownHour"] as? UInt8 ?? 0
        cannulaVolume = rawValue["cannulaVolume"] as? UInt16 ?? 0
        refillAmount = rawValue["refillAmount"] as? UInt16 ?? 0
        targetBg = rawValue["targetBg"] as? UInt16
        useSilentTones = rawValue["useSilentTones"] as? Bool ?? true
        batteryRemaining = rawValue["batteryRemaining"] as? Double ?? 0
        basalProfileNumber = rawValue["basalProfileNumber"] as? UInt8 ?? 0
        cannulaDate = rawValue["cannulaDate2"] as? Date
        reservoirDate = rawValue["reservoirDate"] as? Date
        allowAutomaticTimeSync = rawValue["allowAutomaticTimeSync"] as? Bool ?? true
        isBolusSyncDisabled = rawValue["isBolusSyncDisabled"] as? Bool ?? false
        batteryAge = rawValue["batteryAge"] as? Date

        if let bolusSpeedRaw = rawValue["bolusSpeed"] as? BolusSpeed.RawValue {
            bolusSpeed = BolusSpeed(rawValue: bolusSpeedRaw) ?? .speed12
        } else {
            bolusSpeed = .speed12
        }

        if let bolusStateRaw = rawValue["bolusState"] as? BolusState.RawValue {
            bolusState = BolusState(rawValue: bolusStateRaw) ?? .noBolus
        } else {
            bolusState = .noBolus
        }

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        }

        if let rawBeepAndAlarmType = rawValue["beepAndAlarm"] as? UInt8 {
            beepAndAlarm = BeepAlarmType(rawValue: rawBeepAndAlarmType) ?? .sound
        } else {
            beepAndAlarm = .sound
        }

        if let pumpTimeZone = rawValue["pumpTimeZone"] as? Int {
            self.pumpTimeZone = TimeZone(secondsFromGMT: pumpTimeZone)
        }

        if let rawBasalDeliveryOrdinal = rawValue["basalDeliveryOrdinal"] as? DanaKitBasal.RawValue {
            basalDeliveryOrdinal = DanaKitBasal(rawValue: rawBasalDeliveryOrdinal) ?? .active
        } else {
            basalDeliveryOrdinal = .active
        }
    }

    public init(basalSchedule: [Double]? = nil) {
        lastStatusDate = Date().addingTimeInterval(.hours(-8))
        lastStatusPumpDateTime = lastStatusDate
        isConnected = false // To prevent having an old isConnected state
        reservoirLevel = 0
        hwModel = 0
        pumpProtocol = 0
        encryptionMode = 0
        isInFetchHistoryMode = false
        ignorePassword = false
        devicePassword = 0
        bolusSpeed = .speed12
        isOnBoarded = false
        basalDeliveryDate = Date.now
        bolusState = .noBolus
        self.basalSchedule = basalSchedule ?? []
        ble5Keys = Data([0, 0, 0, 0, 0, 0])
        pairingKey = Data([0, 0, 0, 0, 0, 0])
        randomPairingKey = Data([0, 0, 0])
        randomSyncKey = 0
        basalDeliveryOrdinal = .active
        isTimeDisplay24H = false
        isButtonScrollOnOff = false
        beepAndAlarm = .sound
        lcdOnTimeInSec = 0
        backlightOnTimInSec = 0
        units = 0
        lowReservoirRate = 0
        selectedLanguage = 0
        shutdownHour = 0
        cannulaVolume = 0
        basalProfileNumber = 0
        refillAmount = 0
        targetBg = nil
        useSilentTones = false
        batteryRemaining = 0
        cannulaDate = nil
        isUsingContinuousMode = false
        allowAutomaticTimeSync = true
        isBolusSyncDisabled = false
        batteryAge = nil
        pumpTimeZone = nil
    }

    public var rawValue: RawValue {
        var value: [String: Any] = [:]

        value["lastStatusDate"] = lastStatusDate
        value["lastStatusPumpDateTime"] = lastStatusPumpDateTime
        value["deviceName"] = deviceName
        value["bleIdentifier"] = bleIdentifier
        value["reservoirLevel"] = reservoirLevel
        value["hwModel"] = hwModel
        value["pumpProtocol"] = pumpProtocol
        value["encryptionMode"] = encryptionMode
        value["isInFetchHistoryMode"] = isInFetchHistoryMode
        value["ignorePassword"] = ignorePassword
        value["devicePassword"] = devicePassword
        value["insulinType"] = insulinType?.rawValue
        value["bolusSpeed"] = bolusSpeed.rawValue
        value["isOnBoarded"] = isOnBoarded
        value["basalDeliveryDate"] = basalDeliveryDate
        value["basalDeliveryOrdinal"] = basalDeliveryOrdinal.rawValue
        value["bolusState"] = bolusState.rawValue
        value["pumpTime"] = pumpTime
        value["pumpTimeSyncedAt"] = pumpTimeSyncedAt
        value["basalSchedule"] = basalSchedule
        value["tempBasalUnits"] = tempBasalUnits
        value["tempBasalDuration"] = tempBasalDuration
        value["ble5Keys"] = ble5Keys
        value["pairingKey"] = pairingKey
        value["randomPairingKey"] = randomPairingKey
        value["randomSyncKey"] = randomSyncKey
        value["isTimeDisplay24H"] = isTimeDisplay24H
        value["isButtonScrollOnOff"] = isButtonScrollOnOff
        value["beepAndAlarm"] = beepAndAlarm.rawValue
        value["lcdOnTimeInSec"] = lcdOnTimeInSec
        value["backlightOnTimInSec"] = backlightOnTimInSec
        value["units"] = units
        value["selectedLanguage"] = selectedLanguage
        value["shutdownHour"] = shutdownHour
        value["cannulaVolume"] = cannulaVolume
        value["refillAmount"] = refillAmount
        value["targetBg"] = targetBg
        value["useSilentTones"] = useSilentTones
        value["batteryRemaining"] = batteryRemaining
        value["basalProfileNumber"] = basalProfileNumber
        value["cannulaDate2"] = cannulaDate // Migration to new value
        value["reservoirDate"] = reservoirDate
        value["isUsingContinuousMode"] = isUsingContinuousMode
        value["allowAutomaticTimeSync"] = allowAutomaticTimeSync
        value["isBolusSyncDisabled"] = isBolusSyncDisabled
        value["batteryAge"] = batteryAge
        value["pumpTimeZone"] = pumpTimeZone?.secondsFromGMT()

        return value
    }

    /// The last moment this state has been updated (only for relavant values like isConnected or reservoirLevel)
    public var lastStatusDate = Date().addingTimeInterval(.hours(-8))
    public var lastStatusPumpDateTime: Date

    public var isOnBoarded = false

    /// The name of the device. Needed for en/de-crypting messages
    public var deviceName: String?

    /// The bluetooth identifier. Used to reconnect to pump
    public var bleIdentifier: String?

    /// Flag for checking if the device is still connected
    public var isConnected: Bool = false

    /// Current reservoir levels
    public var reservoirLevel: Double = 0

    /// The hardware model of the pump. Dertermines the friendly device name
    public var hwModel: UInt8 = 0x00
    public var usingUtc: Bool {
        hwModel >= 7
    }

    /// Pump protocol
    public var pumpProtocol: UInt8 = 0x00
    public var encryptionMode: UInt8 = 0x00 // 0x00 = DEFAULT, 0x01 = RS, 0x02 = BLE5

    public var bolusSpeed: BolusSpeed = .speed12

    public var batteryAge: Date?
    public var batteryRemaining: Double = 0

    public var isPumpSuspended: Bool = false

    public var isTempBasalInProgress: Bool = false

    public var bolusState: BolusState = .noBolus

    public var insulinType: InsulinType?

    /// The pump should be in history fetch mode, before requesting history data
    public var isInFetchHistoryMode: Bool = false

    public var ignorePassword: Bool = false
    public var devicePassword: UInt16 = 0

    public var basalSchedule: [Double]

    public var ble5Keys = Data([0, 0, 0, 0, 0, 0])

    public var pairingKey = Data([0, 0, 0, 0, 0, 0])
    public var randomPairingKey = Data([0, 0, 0])
    public var randomSyncKey: UInt8 = 0

    public var pumpTime: Date? {
        didSet {
            pumpTimeSyncedAt = Date.now
        }
    }

    public var pumpTimeZone: TimeZone?

    public var pumpTimeSyncedAt: Date?

    public var basalProfileNumber: UInt8 = 0

    public var reservoirDate: Date?
    public var cannulaDate: Date?

    /// User options
    public var isTimeDisplay24H: Bool
    public var isButtonScrollOnOff: Bool
    public var beepAndAlarm: BeepAlarmType
    public var lcdOnTimeInSec: UInt8
    public var backlightOnTimInSec: UInt8
    public var selectedLanguage: UInt8
    public var units: UInt8
    public var shutdownHour: UInt8
    public var lowReservoirRate: UInt8
    public var cannulaVolume: UInt16
    public var refillAmount: UInt16
    public var targetBg: UInt16?

    public var basalDeliveryDate = Date.now
    public var basalDeliveryOrdinal: DanaKitBasal = .active
    public var tempBasalUnits: Double?
    public var tempBasalDuration: Double?
    public var tempBasalEndsAt: Date {
        basalDeliveryDate + (tempBasalDuration ?? 0)
    }

    public var basalDeliveryState: PumpManagerStatus.BasalDeliveryState {
        switch basalDeliveryOrdinal {
        case .active:
            return .active(basalDeliveryDate)
        case .suspended:
            return .suspended(basalDeliveryDate)
        case .tempBasal:
            return .tempBasal(
                DoseEntry.tempBasal(
                    absoluteUnit: tempBasalUnits ?? 0,
                    duration: tempBasalDuration ?? 0,
                    insulinType: insulinType!,
                    startDate: basalDeliveryDate
                )
            )
        }
    }

    /// Special feature against red loops / ios suspending the app
    public var useSilentTones: Bool = false

    /// Another special feature against red loops / ios suspending the app
    public var isUsingContinuousMode = false

    /// Allows the user to skip bolus syncing to prevent possible double Bolus entries
    public var isBolusSyncDisabled: Bool = false

    /// Allows DanaKit to automaticly sync the time every evening
    public var allowAutomaticTimeSync: Bool = true

    func shouldShowTimeWarning() -> Bool {
        guard let pumpTime = self.pumpTime, let syncedAt = pumpTimeSyncedAt else {
            return false
        }

        // Allow a 15 sec diff in time
        return abs(syncedAt.timeIntervalSince1970 - pumpTime.timeIntervalSince1970) > 15
    }

    mutating func resetState() {
        ignorePassword = false
        devicePassword = 0
        isInFetchHistoryMode = false
    }

    func getFriendlyDeviceName() -> String {
        switch hwModel {
        case 0x01:
            return "DanaR Korean"

        case 0x03:
            switch pumpProtocol {
            case 0x00:
                return "DanaR old"
            case 0x02:
                return "DanaR v2"
            default:
                return "DanaR" // 0x01 and 0x03 known
            }

        case 0x05:
            return pumpProtocol < 10 ? "DanaRS" : "DanaRS v3"

        case 0x06:
            return "DanaRS Korean"

        case 0x07:
            return "Dana-i (BLE4.2)"

        case 0x09:
            return "Dana-i (BLE5)"
        case 0x0A:
            return "Dana-i (BLE5, Korean)"
        default:
            return "Unknown Dana pump"
        }
    }

    func getDanaPumpImageName() -> String {
        switch hwModel {
        case 0x03:
            return "danars"
        case 0x05:
            return "danars"
        case 0x06:
            return "danars"

        case 0x07:
            return "danai"
        case 0x09:
            return "danai"
        case 0x0A:
            return "danai"

        default:
            return "danai"
        }
    }

    static func convertBasal(_ scheduleItems: [RepeatingScheduleValue<Double>]) -> [Double] {
        let basalIntervals: [TimeInterval] = Array(0 ..< 24).map({ TimeInterval(60 * 60 * $0) })
        var output: [Double] = []

        var currentIndex = 0
        for i in 0 ..< 24 {
            if currentIndex >= scheduleItems.count {
                output.append(scheduleItems[currentIndex - 1].value)
            } else if scheduleItems[currentIndex].startTime != basalIntervals[i] {
                output.append(scheduleItems[currentIndex - 1].value)
            } else {
                output.append(scheduleItems[currentIndex].value)
                currentIndex += 1
            }
        }

        return output
    }

    private static func getEncryptionMode(_ hwModel: UInt8) -> UInt8 {
        if hwModel < 0x04 {
            // DEFAULT -> DanaR
            return 0
        }

        if hwModel <= 0x07 {
            // DanaRS & Dana-i (BLE4)
            return 1
        }

        // Dana-i (BLE5)
        return 2
    }
}

extension DanaKitPumpManagerState: CustomDebugStringConvertible {
    public var debugDescription: String {
        [
            "## DanaKitPumpManagerState - \(Date.now)",
            "* isOnboarded: \(isOnBoarded)",
            "* deviceName: \(deviceName ?? "<EMPTY>")",
            "* bleIdentifier: \(bleIdentifier ?? "<EMPTY>")",
            "* friendlyDeviceName: \(getFriendlyDeviceName())",
            "* hwModel: \(hwModel)",
            "* pumpProtocol: \(pumpProtocol)",
            "* lastStatusDate: \(lastStatusDate)",
            "* pumpTime: \(pumpTime ?? Date.distantPast)",
            "* insulinType: \(insulinType ?? .none)",
            "* reservoirLevel: \(reservoirLevel)",
            "* bolusState: \(bolusState.rawValue)",
            "* basalDeliveryOrdinal: \(basalDeliveryOrdinal)",
            "* basalProfileNumber: \(basalProfileNumber)",
            "* isInFetchHistoryMode: \(isInFetchHistoryMode)",
            "* isUsingContinuousMode: \(isUsingContinuousMode)",
            "* useSilentTones: \(useSilentTones)",
            "* isBolusSyncDisabled: \(isBolusSyncDisabled)",
            "* allowAutomaticTimeSync: \(allowAutomaticTimeSync)",
            "* reservoirDate: \(reservoirDate ?? Date.distantPast)",
            "* cannulaDate: \(cannulaDate ?? Date.distantPast)"
        ].joined(separator: "\n")
    }
}
