import Foundation

public struct SimulatedPumpState {
    public var patchState: PatchState = .idle
    public var reservoir: Double = 200
    public var batteryVoltage: Double = 2.80
    public var basalRate: Double = 1.0
    public var basalType: UInt8 = 1
    public var basalSequence: UInt16 = 1
    public var patchID: UInt16 = 41
    public var basalStartedAt = Date()
    public var activatedAt = Date()
    public var pumpTime = Date()
    public var bolusRequested: Double?
    public var bolusDelivered: Double = 0
    public var bolusStartedAt: Date?
    public var tempBasalEndsAt: Date?
    public var suspendStartedAt: Date?
    public var primeStartedAt: Date?
    public var subscribed = false
    public var authorized = false
    public var alarm: AlarmInjection = .none

    public init() {}
}

public struct ProtocolOutcome {
    public let response: MedtrumResponse
    public let shouldNotifyState: Bool
    public let event: String

    public init(response: MedtrumResponse, shouldNotifyState: Bool, event: String) {
        self.response = response
        self.shouldNotifyState = shouldNotifyState
        self.event = event
    }
}

public final class MedtrumProtocolEngine {
    public private(set) var state: SimulatedPumpState
    private let now: () -> Date

    public init(state: SimulatedPumpState = .init(), now: @escaping () -> Date = Date.init) {
        self.state = state
        self.now = now
    }

    public func reset() {
        state = SimulatedPumpState()
    }

    public func setReservoir(_ units: Double) {
        state.reservoir = min(300, max(0, units))
    }

    public func setBattery(_ volts: Double) {
        state.batteryVoltage = min(3.3, max(0, volts))
    }

    public func setBasalRate(_ unitsPerHour: Double) {
        state.basalRate = min(25, max(0, unitsPerHour))
    }

    public func inject(_ alarm: AlarmInjection) {
        state.alarm = alarm
        switch alarm {
        case .occlusion: state.patchState = .occlusion
        case .patchFault: state.patchState = .patchFault
        case .baseFault: state.patchState = .baseFault
        case .reservoirEmpty: state.patchState = .reservoirEmpty
        case .batteryOut: state.patchState = .batteryOut
        case .none, .lowBattery, .lowReservoir, .expiresSoon:
            if state.patchState.rawValue >= PatchState.active.rawValue {
                state.patchState = .active
            }
        }
    }

    public func handle(_ request: MedtrumRequest) -> ProtocolOutcome {
        guard let command = MedtrumCommand(rawValue: request.command) else {
            return outcome(request, code: 1, event: "Unsupported opcode \(request.command)")
        }

        switch command {
        case .authorize:
            // Real pumps validate session token + serial-derived key. The training peripheral
            // accepts them but never stores either credential.
            guard request.payload.count == 9, request.payload[0] == 2 else {
                return outcome(request, code: 7, event: "Authorization rejected")
            }
            state.authorized = true
            return outcome(request, payload: Data([0, 80, 12, 1, 3]), event: "Authorized training session")

        case .synchronize:
            return outcome(request, payload: synchronizationPayload(), event: "State synchronized")

        case .subscribe:
            state.subscribed = true
            return outcome(request, event: "Notifications subscribed")

        case .setTime:
            if let seconds: UInt32 = request.payload.littleEndianInteger(at: 1) {
                state.pumpTime = medtrumDate(seconds)
            }
            return outcome(request, event: "Pump time updated")

        case .getTime:
            return outcome(request, payload: medtrumSeconds(state.pumpTime).littleEndianData, event: "Pump time read")

        case .setTimeZone:
            if let seconds: UInt32 = request.payload.littleEndianInteger(at: 2) {
                state.pumpTime = medtrumDate(seconds)
            }
            return outcome(request, event: "Time zone updated")

        case .prime:
            guard state.patchState.rawValue < PatchState.priming.rawValue else {
                return outcome(request, event: "Patch already primed")
            }
            state.patchState = .priming
            state.primeStartedAt = now()
            return outcome(request, notify: true, event: "Priming started")

        case .activate:
            state.patchState = .active
            state.activatedAt = now()
            state.basalStartedAt = now()
            state.basalType = 1
            state.basalSequence &+= 1
            return outcome(request, payload: activationPayload(), notify: true, event: "Training patch activated")

        case .setBolus:
            guard state.patchState == .active,
                  let ticks: UInt16 = request.payload.littleEndianInteger(at: 1)
            else {
                return outcome(request, code: 8, event: "Bolus rejected in current state")
            }
            state.bolusRequested = Double(ticks) * 0.05
            state.bolusDelivered = 0
            state.bolusStartedAt = now()
            return outcome(request, notify: true, event: "Bolus started: \(format(state.bolusRequested ?? 0)) U")

        case .cancelBolus:
            state.bolusRequested = nil
            state.bolusStartedAt = nil
            return outcome(request, notify: true, event: "Bolus cancelled")

        case .setBasalProfile:
            if let firstRate = firstBasalRate(from: request.payload) {
                state.basalRate = firstRate
            }
            state.basalType = 1
            state.basalStartedAt = now()
            state.basalSequence &+= 1
            return outcome(request, payload: basalCommandPayload(), notify: true, event: "Basal profile updated")

        case .setTempBasal:
            guard let ticks: UInt16 = request.payload.littleEndianInteger(at: 1),
                  let minutes: UInt16 = request.payload.littleEndianInteger(at: 3)
            else {
                return outcome(request, code: 1, event: "Malformed temp basal")
            }
            state.basalRate = Double(ticks) * 0.05
            state.basalType = 6
            state.basalStartedAt = now()
            state.tempBasalEndsAt = now().addingTimeInterval(Double(minutes) * 60)
            state.basalSequence &+= 1
            return outcome(request, payload: basalCommandPayload(), notify: true, event: "Temp basal set")

        case .cancelTempBasal:
            state.basalType = 1
            state.tempBasalEndsAt = nil
            state.basalStartedAt = now()
            state.basalSequence &+= 1
            return outcome(request, payload: basalCommandPayload(), notify: true, event: "Temp basal cancelled")

        case .suspendPump:
            state.patchState = .suspended
            state.basalType = 18
            state.suspendStartedAt = now()
            return outcome(request, notify: true, event: "Delivery suspended")

        case .resumePump:
            state.patchState = .active
            state.basalType = 1
            state.suspendStartedAt = nil
            state.basalStartedAt = now()
            return outcome(request, notify: true, event: "Delivery resumed")

        case .stopPatch:
            state.patchState = .stopped
            return outcome(
                request,
                payload: state.basalSequence.littleEndianData + state.patchID.littleEndianData,
                notify: true,
                event: "Training patch stopped"
            )

        case .setPatch:
            return outcome(request, event: "Patch settings updated")

        case .clearAlarm:
            state.alarm = .none
            if state.patchState.rawValue >= PatchState.active.rawValue {
                state.patchState = .active
            }
            return outcome(request, payload: Data([0, 0]), notify: true, event: "Alarm cleared")

        case .getRecord:
            return outcome(request, code: 1, event: "History record opcode not implemented")
        }
    }

    /// Advances priming, bolus, and temporary basal state. Returns true when Trio should be notified.
    @discardableResult
    public func advance(to date: Date? = nil) -> Bool {
        let current = date ?? now()
        var changed = false

        if state.patchState == .priming,
           let started = state.primeStartedAt,
           current.timeIntervalSince(started) >= 3
        {
            state.patchState = .primed
            state.primeStartedAt = nil
            changed = true
        }

        if let requested = state.bolusRequested, let started = state.bolusStartedAt {
            let delivered = min(requested, current.timeIntervalSince(started) * 1.5 / 60)
            if delivered > state.bolusDelivered {
                state.reservoir = max(0, state.reservoir - (delivered - state.bolusDelivered))
                state.bolusDelivered = delivered
                changed = true
            }
            if delivered >= requested {
                // Keep the completed bolus in one notification; the next tick clears it.
                state.bolusStartedAt = nil
            }
        } else if state.bolusRequested != nil {
            state.bolusRequested = nil
            changed = true
        }

        if let end = state.tempBasalEndsAt, current >= end {
            state.tempBasalEndsAt = nil
            state.basalType = 1
            state.basalStartedAt = current
            state.basalSequence &+= 1
            changed = true
        }
        return changed
    }

    public func heartbeatValue() -> Data {
        var mask: UInt16 = 0x20 // reservoir
        if state.bolusRequested != nil {
            mask |= 0x02
        } else if state.patchState == .priming || state.patchState == .primed {
            mask |= 0x10
        } else {
            mask |= 0x08
        }
        if alarmFlags() != 0 {
            mask |= 0x200
        }

        var data = Data([state.patchState.rawValue])
        data.append(mask.littleEndianData)
        if mask & 0x02 != 0 {
            let completed = state.bolusStartedAt == nil
            data.append(completed ? UInt8(0x81) : UInt8(0x01))
            data.append(UInt16((state.bolusDelivered / 0.05).rounded()).littleEndianData)
        }
        if mask & 0x08 != 0 {
            data.append(basalStatusPayload())
        }
        if mask & 0x10 != 0 {
            data.append(state.patchState == .primed ? 240 : 120)
        }
        data.append(UInt16((state.reservoir / 0.05).rounded()).littleEndianData)
        if mask & 0x200 != 0 {
            data.append(alarmFlags().littleEndianData)
            data.append(UInt16(0).littleEndianData)
        }
        return data
    }

    private func outcome(
        _ request: MedtrumRequest,
        code: UInt16 = 0,
        payload: Data = Data(),
        notify: Bool = false,
        event: String
    ) -> ProtocolOutcome {
        ProtocolOutcome(
            response: MedtrumResponse(
                command: request.command,
                sequence: request.sequence,
                responseCode: code,
                payload: payload
            ),
            shouldNotifyState: notify,
            event: event
        )
    }

    private func synchronizationPayload() -> Data {
        synchronizationBody()
    }

    private func synchronizationBody() -> Data {
        var mask: UInt16 = 0x7E8 // basal, reservoir, start, battery, storage, alarm, age
        if state.bolusRequested != nil {
            mask |= 0x02
        }
        if state.patchState == .suspended {
            mask |= 0x01
        }

        var data = Data([state.patchState.rawValue])
        data.append(mask.littleEndianData)
        if mask & 0x01 != 0 {
            data.append(medtrumSeconds(state.suspendStartedAt ?? now()).littleEndianData)
        }
        if mask & 0x02 != 0 {
            let completed = state.bolusStartedAt == nil
            data.append((completed ? UInt8(0x81) : UInt8(0x01)))
            data.append(UInt16((state.bolusDelivered / 0.05).rounded()).littleEndianData)
        }
        data.append(basalStatusPayload())
        data.append(UInt16((state.reservoir / 0.05).rounded()).littleEndianData)
        data.append(medtrumSeconds(state.activatedAt).littleEndianData)
        data.append(batteryPayload())
        data.append(state.basalSequence.littleEndianData)
        data.append(state.patchID.littleEndianData)
        data.append(alarmFlags().littleEndianData)
        data.append(UInt16(0).littleEndianData)
        data.append(UInt32(max(0, now().timeIntervalSince(state.activatedAt))).littleEndianData)
        return data
    }

    private func basalStatusPayload() -> Data {
        var data = Data([state.basalType])
        data.append(state.basalSequence.littleEndianData)
        data.append(state.patchID.littleEndianData)
        data.append(medtrumSeconds(state.basalStartedAt).littleEndianData)

        let deliveryTicks: UInt32 = 0
        let rateTicks = UInt32((state.basalRate / 0.05).rounded()) & 0x0FFF
        let packed = (deliveryTicks << 12) | rateTicks
        data.append(contentsOf: packed.littleEndianData.prefix(3))
        return data
    }

    private func basalCommandPayload() -> Data {
        var data = Data([state.basalType])
        data.append(UInt16((state.basalRate / 0.05).rounded()).littleEndianData)
        data.append(state.basalSequence.littleEndianData)
        data.append(state.patchID.littleEndianData)
        data.append(medtrumSeconds(state.basalStartedAt).littleEndianData)
        return data
    }

    private func activationPayload() -> Data {
        var data = Data()
        data.append(UInt32(state.patchID).littleEndianData)
        data.append(medtrumSeconds(now()).littleEndianData)
        data.append(basalCommandPayload())
        return data
    }

    private func batteryPayload() -> Data {
        let a = UInt32((min(7.99, state.batteryVoltage + 0.1) * 512).rounded()) & 0x0FFF
        let b = UInt32((min(7.99, state.batteryVoltage) * 512).rounded()) & 0x0FFF
        return Data(((b << 12) | a).littleEndianData.prefix(3))
    }

    private func alarmFlags() -> UInt16 {
        switch state.alarm {
        case .lowBattery: 1
        case .lowReservoir: 2
        case .expiresSoon: 4
        default: 0
        }
    }

    private func firstBasalRate(from payload: Data) -> Double? {
        // byte 0 is profile type; byte 1 is entry count; each entry packs minute + rate.
        guard payload.count >= 5 else { return nil }
        let packed = UInt32(payload[2]) | UInt32(payload[3]) << 8 | UInt32(payload[4]) << 16
        return Double(packed >> 12) * 0.05
    }

    private func medtrumDate(_ seconds: UInt32) -> Date {
        Date(timeIntervalSince1970: 1_388_534_400 + Double(seconds))
    }

    private func medtrumSeconds(_ date: Date) -> UInt32 {
        UInt32(max(0, date.timeIntervalSince1970 - 1_388_534_400))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
