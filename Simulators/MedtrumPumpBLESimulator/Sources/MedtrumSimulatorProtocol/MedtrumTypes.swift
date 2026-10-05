import Foundation

public enum MedtrumUUID {
    public static let service = "669A9001-0008-968F-E311-6050405558B3"
    public static let read = "669A9120-0008-968F-E311-6050405558B3"
    public static let write = "669A9101-0008-968F-E311-6050405558B3"
}

public enum MedtrumCommand: UInt8, CaseIterable {
    case synchronize = 3
    case subscribe = 4
    case authorize = 5
    case setTime = 10
    case getTime = 11
    case setTimeZone = 12
    case prime = 16
    case activate = 18
    case setBolus = 19
    case cancelBolus = 20
    case setBasalProfile = 21
    case setTempBasal = 24
    case cancelTempBasal = 25
    case suspendPump = 28
    case resumePump = 29
    case stopPatch = 31
    case setPatch = 35
    case getRecord = 99
    case clearAlarm = 115
}

public enum PatchState: UInt8, CaseIterable, Identifiable {
    case idle = 1
    case filled = 2
    case priming = 3
    case primed = 4
    case active = 32
    case suspended = 69
    case occlusion = 96
    case expired = 97
    case reservoirEmpty = 98
    case patchFault = 99
    case baseFault = 101
    case batteryOut = 102
    case stopped = 128

    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .idle: "Idle"
        case .filled: "Filled"
        case .priming: "Priming"
        case .primed: "Primed"
        case .active: "Active"
        case .suspended: "Suspended"
        case .occlusion: "Occlusion"
        case .expired: "Expired"
        case .reservoirEmpty: "Reservoir empty"
        case .patchFault: "Patch fault"
        case .baseFault: "Base fault"
        case .batteryOut: "Battery empty"
        case .stopped: "Stopped"
        }
    }
}

public enum AlarmInjection: String, CaseIterable, Identifiable {
    case none = "None"
    case lowBattery = "Low battery"
    case lowReservoir = "Low reservoir"
    case expiresSoon = "Expires soon"
    case occlusion = "Occlusion"
    case patchFault = "Patch fault"
    case baseFault = "Base fault"
    case reservoirEmpty = "Reservoir empty"
    case batteryOut = "Battery empty"

    public var id: String { rawValue }
}

public struct MedtrumRequest: Equatable {
    public let command: UInt8
    public let sequence: UInt8
    public let payload: Data

    public init(command: UInt8, sequence: UInt8, payload: Data) {
        self.command = command
        self.sequence = sequence
        self.payload = payload
    }
}

public struct MedtrumResponse: Equatable {
    public let command: UInt8
    public let sequence: UInt8
    public let responseCode: UInt16
    public let payload: Data

    public init(command: UInt8, sequence: UInt8, responseCode: UInt16 = 0, payload: Data = Data()) {
        self.command = command
        self.sequence = sequence
        self.responseCode = responseCode
        self.payload = payload
    }
}

extension FixedWidthInteger {
    public var littleEndianData: Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}

extension Data {
    public func littleEndianInteger<T: FixedWidthInteger>(at offset: Int, as: T.Type = T.self) -> T? {
        guard offset >= 0, count >= offset + MemoryLayout<T>.size else { return nil }
        return self[offset ..< offset + MemoryLayout<T>.size].enumerated().reduce(0) {
            $0 | (T($1.element) << T($1.offset * 8))
        }
    }
}
