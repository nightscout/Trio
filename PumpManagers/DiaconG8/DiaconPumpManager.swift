// DiaconPumpManager.swift
// Trio iAPS에 G8 펌프를 연동하기 위한 PumpManager 구현 뼈대

import Foundation
import LoopKit

class DiaconPumpManager: PumpManager {
    static let managerIdentifier = "DiaconG8"

    var pumpDelegate: PumpManagerDelegate?
    var status: PumpManagerStatus
    let bleManager = DiaconnBLEManager()
    var seq: UInt8 = 0

    init() {
        status = PumpManagerStatus(battery: nil, reservoir: nil)
    }

    var device: HKDevice? {
        return HKDevice(
            name: "Diacon G8",
            manufacturer: "G2E",
            model: "G8",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    func incrementSeq() -> UInt8 {
        seq = (seq + 1) % 255
        return seq
    }

    // MARK: - Basic Required Functions

    var managerDisplayName: String { return "Diacon G8" }
    var state: PumpManagerState { return EmptyPumpManagerState() }

    func deliverBolus(units: Double, automatic: Bool, completion: @escaping (Result<BolusDeliveryState, Error>) -> Void) {
        let packet = DiaconnG8Packet.buildBolusCommand(units: units, seq: incrementSeq())
        bleManager.send(packet)
        completion(.success(.init(units: units, startTime: Date())))
    }

    func enactTempBasal(rate: Double, duration: TimeInterval, completion: @escaping (Result<TempBasalRecommendation, Error>) -> Void) {
        let minutes = Int(duration / 60)
        let packet = DiaconnG8Packet.buildTempBasalCommand(rate: rate, durationMin: minutes, seq: incrementSeq())
        bleManager.send(packet)
        completion(.success(.init(rate: rate, duration: duration)))
    }

    // 기타 필수 함수 구현은 차차 확장

    func assertCurrentPumpData(completion: @escaping (Result<PumpManagerStatus, Error>) -> Void) {
        completion(.success(status))
    }

    func suspendDelivery(completion: @escaping (Error?) -> Void) {
        // Not supported yet
        completion(nil)
    }

    func resumeDelivery(completion: @escaping (Error?) -> Void) {
        // Not supported yet
        completion(nil)
    }

    func updateDeliveryLimitSettings(_ settings: DeliveryLimitSettings, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func setTime(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func updateFirmware(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}
