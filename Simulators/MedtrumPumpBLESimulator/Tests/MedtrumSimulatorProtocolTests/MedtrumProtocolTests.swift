import Foundation
@testable import MedtrumSimulatorProtocol
import XCTest

final class MedtrumProtocolTests: XCTestCase {
    func testCRCMatchesMedtrumKitFixtures() {
        XCTAssertEqual(MedtrumCRC8.calculate(Data([5, 3, 0, 0])), 0xFC)
        XCTAssertEqual(MedtrumCRC8.calculate(Data([10, 24, 0, 0, 6, 25, 0, 60, 0])), 0x3B)
    }

    func testAssemblerAcceptsSingleFrameTransportPadding() throws {
        var frame = Data([5, 3, 7, 0])
        frame.append(MedtrumCRC8.calculate(frame))
        frame.append(0)
        var assembler = MedtrumRequestAssembler()
        let request = try XCTUnwrap(assembler.append(frame))
        XCTAssertEqual(request, MedtrumRequest(command: 3, sequence: 7, payload: Data()))
    }

    func testAssemblerReassemblesMedtrumKitActivationFixture() throws {
        var assembler = MedtrumRequestAssembler()
        let first = Data([29, 18, 0, 1, 0, 12, 1, 6, 0, 0, 30, 32, 3, 16, 14, 0, 0, 1, 3, 150])
        let second = Data([29, 18, 0, 2, 16, 14, 0, 0, 1, 2, 12, 12, 12, 217, 9])
        XCTAssertNil(try assembler.append(first))
        let request = try XCTUnwrap(assembler.append(second))
        XCTAssertEqual(request.command, MedtrumCommand.activate.rawValue)
        XCTAssertEqual(request.payload.count, 24)
    }

    func testResponseEncoderPreservesHeaderSequenceAndCRC() {
        let response = MedtrumResponse(command: 11, sequence: 12, payload: UInt32(1234).littleEndianData)
        let frames = MedtrumResponseEncoder.encode(response)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0][0], 10)
        XCTAssertEqual(frames[0][1], 11)
        XCTAssertEqual(frames[0][2], 12)
        XCTAssertEqual(MedtrumCRC8.calculate(Data(frames[0].dropLast())), frames[0].last)
    }

    func testConnectHandshakeAndFullSyncAreDriverCompatible() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let engine = MedtrumProtocolEngine(now: { fixedNow })

        let authorization = engine.handle(
            MedtrumRequest(command: 5, sequence: 0, payload: Data([2, 1, 2, 3, 4, 5, 6, 7, 8]))
        )
        XCTAssertEqual(authorization.response.responseCode, 0)
        XCTAssertEqual(authorization.response.payload, Data([0, 80, 12, 1, 3]))

        let sync = engine.handle(MedtrumRequest(command: 3, sequence: 1, payload: Data()))
        XCTAssertEqual(sync.response.payload[0], PatchState.idle.rawValue)
        let mask: UInt16? = sync.response.payload.littleEndianInteger(at: 1)
        XCTAssertEqual(mask, 0x7E8)

        let subscribe = engine.handle(
            MedtrumRequest(command: 4, sequence: 2, payload: Data([0xFF, 0x0F]))
        )
        XCTAssertEqual(subscribe.response.responseCode, 0)
        XCTAssertTrue(engine.state.subscribed)
    }

    func testTherapyCommandsMutateSimulationState() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var current = start
        let engine = MedtrumProtocolEngine(now: { current })

        _ = engine.handle(MedtrumRequest(command: 18, sequence: 0, payload: Data()))
        XCTAssertEqual(engine.state.patchState, .active)

        _ = engine.handle(
            MedtrumRequest(command: 24, sequence: 1, payload: Data([6, 25, 0, 60, 0]))
        )
        XCTAssertEqual(engine.state.basalRate, 1.25)
        XCTAssertEqual(engine.state.basalType, 6)

        _ = engine.handle(
            MedtrumRequest(command: 19, sequence: 2, payload: Data([1, 20, 0, 0]))
        )
        current = start.addingTimeInterval(20)
        XCTAssertTrue(engine.advance())
        XCTAssertEqual(engine.state.bolusDelivered, 0.5, accuracy: 0.001)

        _ = engine.handle(MedtrumRequest(command: 20, sequence: 3, payload: Data([1])))
        XCTAssertNil(engine.state.bolusRequested)

        _ = engine.handle(MedtrumRequest(command: 28, sequence: 4, payload: Data([3, 120])))
        XCTAssertEqual(engine.state.patchState, .suspended)
        _ = engine.handle(MedtrumRequest(command: 29, sequence: 5, payload: Data()))
        XCTAssertEqual(engine.state.patchState, .active)
    }

    func testInjectedFaultAppearsInHeartbeat() {
        let engine = MedtrumProtocolEngine()
        _ = engine.handle(MedtrumRequest(command: 18, sequence: 0, payload: Data()))
        engine.inject(.occlusion)
        XCTAssertEqual(engine.state.patchState, .occlusion)
        XCTAssertEqual(engine.heartbeatValue()[0], PatchState.occlusion.rawValue)
    }
}
