//
//  RileyLinkDeviceError.swift
//  RileyLinkBLEKit
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//


public enum RileyLinkDeviceError: Error {
    case peripheralManagerError(LocalizedError)
    case errorResponse(String)
    case writeSizeLimitExceeded(maxLength: Int)
    case invalidResponse(Data)
    case responseTimeout
    case commandsBlocked
    case unsupportedCommand(String)
}


extension RileyLinkDeviceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .peripheralManagerError(let error):
            return error.errorDescription
        case .errorResponse(let message):
            return message
        case .invalidResponse(let response):
            return String(format: LocalizedString("Response %@ is invalid", comment: "Invalid response error description (1: response)"), String(describing: response))
        case .writeSizeLimitExceeded(let maxLength):
            return String(format: LocalizedString("Data exceeded maximum size of %@ bytes", comment: "Write size limit exceeded error description (1: size limit)"), NumberFormatter.localizedString(from: NSNumber(value: maxLength), number: .none))
        case .responseTimeout:
            return LocalizedString("Pump did not respond in time", comment: "Response timeout error description")
        case .commandsBlocked:
            return LocalizedString("RileyLink command did not respond", comment: "commandsBlocked error description")
        case .unsupportedCommand(let command):
            return String(format: LocalizedString("RileyLink firmware does not support the %@ command", comment: "Unsupported command error description"), String(describing: command))
        }
    }

    public var failureReason: String? {
        switch self {
        case .peripheralManagerError(let error):
            return error.failureReason
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .peripheralManagerError(let error):
            return error.recoverySuggestion
        case .commandsBlocked:
            return LocalizedString("RileyLink may need to be turned off and back on", comment: "commandsBlocked recovery suggestion")
        default:
            return nil
        }
    }
}
