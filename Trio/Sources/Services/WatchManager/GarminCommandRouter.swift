import Foundation

/// A message received from a Connect IQ app, after envelope validation.
enum GarminInboundMessage: Equatable {
    /// Bare `"status"` string sent by watch apps that predate the v1 envelope.
    case legacyStatus
    case status
    case presets
    /// `requestIDString` is echoed back verbatim so the watch can match the ack.
    case command(requestIDString: String, requestID: UUID, date: Date, command: WatchCommand)
    /// Malformed or unsupported; carries the request ID when the envelope still named one to answer.
    case invalid(requestID: String?)
}

/// Garmin v1 wire contract: parsing inbound envelopes and building the targeted responses.
enum GarminCommandEnvelope {
    static let protocolVersion = 1

    enum Request: String {
        case status
        case presets
        case command
        case ack
    }

    private static let readEnvelopeKeys: Set<String> = [WatchMessageKeys.protocolVersion, WatchMessageKeys.request]
    private static let commandEnvelopeKeys: Set<String> = [
        WatchMessageKeys.protocolVersion,
        WatchMessageKeys.request,
        WatchMessageKeys.requestID,
        WatchMessageKeys.date,
        WatchMessageKeys.command,
        WatchMessageKeys.payload
    ]

    static func parse(_ message: Any) -> GarminInboundMessage {
        if let string = message as? String {
            return string == Request.status.rawValue ? .legacyStatus : .invalid(requestID: nil)
        }
        guard let envelope = message as? [String: Any] else {
            return .invalid(requestID: nil)
        }

        let requestIDString = envelope[WatchMessageKeys.requestID] as? String
        let keys = Set(envelope.keys)
        guard integer(envelope[WatchMessageKeys.protocolVersion]) == Int64(protocolVersion),
              let request = (envelope[WatchMessageKeys.request] as? String).flatMap(Request.init(rawValue:))
        else {
            return .invalid(requestID: requestIDString)
        }

        switch request {
        case .status:
            return keys == readEnvelopeKeys ? .status : .invalid(requestID: requestIDString)
        case .presets:
            return keys == readEnvelopeKeys ? .presets : .invalid(requestID: requestIDString)
        case .command:
            guard keys == commandEnvelopeKeys,
                  let requestIDString,
                  let requestID = rfc4122UUID(requestIDString),
                  let milliseconds = integer(envelope[WatchMessageKeys.date]), milliseconds >= 0,
                  let name = envelope[WatchMessageKeys.command] as? String,
                  let payload = envelope[WatchMessageKeys.payload] as? [String: Any],
                  let command = command(named: name, payload: payload)
            else {
                return .invalid(requestID: requestIDString)
            }
            let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
            return .command(requestIDString: requestIDString, requestID: requestID, date: date, command: command)
        case .ack:
            return .invalid(requestID: requestIDString)
        }
    }

    static func acknowledgment(requestID: String, result: WatchCommandResult) -> [String: Any] {
        [
            WatchMessageKeys.protocolVersion: protocolVersion,
            WatchMessageKeys.request: Request.ack.rawValue,
            WatchMessageKeys.requestID: requestID,
            WatchMessageKeys.acknowledged: result.acknowledged,
            WatchMessageKeys.ackCode: result.ackCode.rawValue,
            WatchMessageKeys.message: result.message
        ]
    }

    /// Lists every configured preset; `isEnabled` reports whether it is running now, not whether
    /// the watch may activate it. The switches and limits let the watch hide what the phone would
    /// refuse; amounts go out as doubles in U and g.
    static func presetsResponse(_ presets: WatchCommandPresets) -> [String: Any] {
        let capabilities = presets.capabilities
        return [
            WatchMessageKeys.protocolVersion: protocolVersion,
            WatchMessageKeys.request: Request.presets.rawValue,
            WatchMessageKeys.overridePresets: presets.overridePresets.map {
                [WatchMessageKeys.presetName: $0.name, WatchMessageKeys.presetIsEnabled: $0.isEnabled] as [String: Any]
            },
            WatchMessageKeys.tempTargetPresets: presets.tempTargetPresets.map {
                [WatchMessageKeys.presetName: $0.name, WatchMessageKeys.presetIsEnabled: $0.isEnabled] as [String: Any]
            },
            WatchMessageKeys.isCommandControlEnabled: capabilities.isCommandControlEnabled,
            WatchMessageKeys.isBolusCommandEnabled: capabilities.isBolusCommandEnabled,
            WatchMessageKeys.maxBolus: NSDecimalNumber(decimal: capabilities.maxBolus).doubleValue,
            WatchMessageKeys.maxCarbs: NSDecimalNumber(decimal: capabilities.maxCarbs).doubleValue,
            WatchMessageKeys.bolusIncrement: NSDecimalNumber(decimal: capabilities.bolusIncrement).doubleValue
        ]
    }

    // MARK: - Payloads

    private static func command(named name: String, payload: [String: Any]) -> WatchCommand? {
        let keys = Set(payload.keys)

        switch name {
        case WatchMessageKeys.bolus:
            guard keys == [WatchMessageKeys.bolus], let units = units(payload[WatchMessageKeys.bolus]) else { return nil }
            return .bolus(units)
        case WatchMessageKeys.carbs:
            guard keys == [WatchMessageKeys.carbs], let grams = grams(payload[WatchMessageKeys.carbs]) else { return nil }
            return .carbs(grams)
        case WatchMessageKeys.mealBolus:
            guard keys == [WatchMessageKeys.carbs, WatchMessageKeys.bolus],
                  let grams = grams(payload[WatchMessageKeys.carbs]),
                  let units = units(payload[WatchMessageKeys.bolus])
            else { return nil }
            return .mealBolus(carbs: grams, bolus: units)
        case WatchMessageKeys.activateOverride:
            guard keys == [WatchMessageKeys.presetName], let name = payload[WatchMessageKeys.presetName] as? String
            else { return nil }
            return .activateOverride(name: name)
        case WatchMessageKeys.cancelOverride:
            return keys.isEmpty ? .cancelOverride : nil
        case WatchMessageKeys.activateTempTarget:
            guard keys == [WatchMessageKeys.presetName], let name = payload[WatchMessageKeys.presetName] as? String
            else { return nil }
            return .activateTempTarget(name: name)
        case WatchMessageKeys.cancelTempTarget:
            return keys.isEmpty ? .cancelTempTarget : nil
        default:
            return nil
        }
    }

    // MARK: - Value Types

    /// Connect IQ delivers every number, and booleans too, as `NSNumber`; booleans are not numbers here.
    private static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue.isFinite ? number : nil
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = number(value) else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 9.0E15 else { return nil }
        return number.int64Value
    }

    private static func grams(_ value: Any?) -> Int? {
        integer(value).flatMap { Int(exactly: $0) }
    }

    /// Rounds to 0.001 U: a Monkey C `Float` of 0.1 arrives as 0.10000000149.
    private static func units(_ value: Any?) -> Decimal? {
        guard let number = number(value) else { return nil }
        var raw = Decimal(number.doubleValue)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 3, .plain)
        return rounded
    }

    static func rfc4122UUID(_ string: String) -> UUID? {
        guard string.count == 36, let uuid = UUID(uuidString: string) else { return nil }
        // variant bits 10xx mark the RFC 4122 layout
        return uuid.uuid.8 & 0xC0 == 0x80 ? uuid : nil
    }
}

/// Connect IQ side of watch commands: turns one inbound message into at most one reply for the
/// requesting app plus an optional state refresh. It has no broadcast path by design.
struct GarminCommandRouter {
    struct Outcome {
        /// Sent to the requesting `IQApp` only.
        var reply: [String: Any]?
        /// Trigger name for a regular watch-state update, if one is due.
        var refreshTrigger: String?
        /// A preset started or stopped, so every Complication app needs the targeted preset list.
        var pushesPresets = false

        static let none = Outcome(reply: nil, refreshTrigger: nil)
    }

    let processor: WatchCommandProcessor
    var log: (String) -> Void = { debug(.watchManager, $0) }

    func route(_ message: Any, from appUUID: UUID, isRegistered: Bool, appName: String) async -> Outcome {
        let inbound = GarminCommandEnvelope.parse(message)
        log("⌚️📥 Garmin: Received \(inbound.logName) from \(appName)")

        guard isRegistered else {
            log("⌚️🔐 Garmin: Ignoring \(inbound.logName) from unregistered app \(appUUID.uuidString)")
            return .none
        }

        switch inbound {
        case .legacyStatus,
             .status:
            return Outcome(reply: nil, refreshTrigger: "WatchRequest")

        case .presets:
            do {
                let presets = try await processor.presets()
                return Outcome(reply: GarminCommandEnvelope.presetsResponse(presets), refreshTrigger: nil)
            } catch {
                log("⌚️❌ Garmin: Loading presets failed (\(WatchCommandErrorCategory.name(for: error)))")
                return .none
            }

        case let .command(requestIDString, requestID, date, command):
            log("⌚️🔐 Garmin: Accepted \(command.name) from registered \(appName)")
            let request = WatchCommandRequest(requestID: requestID, appUUID: appUUID, date: date, command: command)
            let result = await processor.process(request)
            return Outcome(
                reply: GarminCommandEnvelope.acknowledgment(requestID: requestIDString, result: result),
                refreshTrigger: result.refreshesState ? "WatchCommand" : nil,
                pushesPresets: result.acknowledged && command.changesPresetState
            )

        case let .invalid(requestID):
            // without a request ID the watch could not match an answer, so none is sent
            guard let requestID else { return .none }
            let result = WatchCommandResult.failure(String(localized: "Invalid command.", comment: "Watch command ack"))
            return Outcome(reply: GarminCommandEnvelope.acknowledgment(requestID: requestID, result: result), refreshTrigger: nil)
        }
    }
}

private extension GarminInboundMessage {
    /// Never includes payload values: a command body can carry an insulin amount.
    var logName: String {
        switch self {
        case .legacyStatus: return "legacy status request"
        case .status: return "status request"
        case .presets: return "presets request"
        case let .command(_, _, _, command): return "\(command.name) command"
        case .invalid: return "invalid message"
        }
    }
}
