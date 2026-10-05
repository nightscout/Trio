import Foundation
import MedtrumSimulatorProtocol

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

check(MedtrumCRC8.calculate(Data([5, 3, 0, 0])) == 0xFC, "CRC fixture")

var assembler = MedtrumRequestAssembler()
var syncFrame = Data([5, 3, 7, 0])
syncFrame.append(MedtrumCRC8.calculate(syncFrame))
syncFrame.append(0)
let syncRequest = try assembler.append(syncFrame)
check(syncRequest == MedtrumRequest(command: 3, sequence: 7, payload: Data()), "single-frame assembly")

let activationFrame1 = Data([29, 18, 0, 1, 0, 12, 1, 6, 0, 0, 30, 32, 3, 16, 14, 0, 0, 1, 3, 150])
let activationFrame2 = Data([29, 18, 0, 2, 16, 14, 0, 0, 1, 2, 12, 12, 12, 217, 9])
let partialActivation = try assembler.append(activationFrame1)
check(partialActivation == nil, "first activation fragment")
let activation = try assembler.append(activationFrame2)
check(activation?.payload.count == 24, "activation reassembly")

let now = Date(timeIntervalSince1970: 1_700_000_000)
let engine = MedtrumProtocolEngine(now: { now })
let authorization = engine.handle(
    MedtrumRequest(command: 5, sequence: 0, payload: Data([2, 1, 2, 3, 4, 5, 6, 7, 8]))
)
check(authorization.response.payload == Data([0, 80, 12, 1, 3]), "authorization response")

let synchronization = engine.handle(MedtrumRequest(command: 3, sequence: 1, payload: Data()))
let mask: UInt16? = synchronization.response.payload.littleEndianInteger(at: 1)
check(mask == 0x7E8, "full synchronization field mask")

_ = engine.handle(MedtrumRequest(command: 18, sequence: 2, payload: Data()))
check(engine.state.patchState == .active, "activation state")
_ = engine.handle(MedtrumRequest(command: 24, sequence: 3, payload: Data([6, 25, 0, 60, 0])))
check(engine.state.basalRate == 1.25 && engine.state.basalType == 6, "temp basal state")
_ = engine.handle(MedtrumRequest(command: 28, sequence: 4, payload: Data([3, 120])))
check(engine.state.patchState == .suspended, "suspend state")
_ = engine.handle(MedtrumRequest(command: 29, sequence: 5, payload: Data()))
check(engine.state.patchState == .active, "resume state")

let encoded = MedtrumResponseEncoder.encode(
    MedtrumResponse(command: 11, sequence: 12, payload: UInt32(1234).littleEndianData)
)
check(encoded.count == 1 && encoded[0][0] == 10 && encoded[0][2] == 12, "response framing")

print("PASS: Medtrum protocol checks")
