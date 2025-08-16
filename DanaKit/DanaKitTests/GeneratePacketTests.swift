@testable import DanaKit
import XCTest

class GeneratePacketTests: XCTestCase {
    func testGenerateBasalCancelTemporary() {
        let packet = generatePacketBasalCancelTemporary()
        let expectedSnapshot = DanaGeneratePacket(opCode: 98, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBasalGetProfileNumber() {
        let packet = generatePacketBasalGetProfileNumber()
        let expectedSnapshot = DanaGeneratePacket(opCode: 101, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBasalGetRate() {
        let packet = generatePacketBasalGetRate()
        let expectedSnapshot = DanaGeneratePacket(opCode: 103, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBasalSetProfileNumber() {
        let options = PacketBasalSetProfileNumber(profileNumber: 0)
        let packet = generatePacketBasalSetProfileNumber(options: options)
        let expectedSnapshot = DanaGeneratePacket(opCode: 100, data: Data([0]))

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBasalSetProfileRate() {
        let profileBasalRate: [Double] = Array(repeating: 0.5, count: 24)
        let options = PacketBasalSetProfileRate(profileNumber: 0, profileBasalRate: profileBasalRate)

        do {
            let packet = try generatePacketBasalSetProfileRate(options: options)
            let expectedData = Data([0] + Array(repeating: [50, 0], count: 24).flatMap { $0 })
            let expectedSnapshot = DanaGeneratePacket(opCode: 102, data: expectedData)

            XCTAssertEqual(packet.type, expectedSnapshot.type)
            XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
            XCTAssertEqual(packet.data, expectedSnapshot.data)
        } catch {
            XCTFail()
        }
    }

    func testGenerateBasalSetProfileRate_InvalidRateLength() {
        let profileBasalRate: [Double] = Array(repeating: 0.5, count: 23)
        let options = PacketBasalSetProfileRate(profileNumber: 0, profileBasalRate: profileBasalRate)

        XCTAssertThrowsError(try generatePacketBasalSetProfileRate(options: options))
    }

    func testGenerateBasalSetSuspendOff() {
        let packet = generatePacketBasalSetSuspendOff()
        let expectedSnapshot = DanaGeneratePacket(opCode: 106, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBasalSetSuspendOn() {
        let packet = generatePacketBasalSetSuspendOn()
        let expectedSnapshot = DanaGeneratePacket(opCode: 105, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBasalSetTemporary() {
        let options = PacketBasalSetTemporary(temporaryBasalRatio: 200, temporaryBasalDuration: 1)
        let packet = generatePacketBasalSetTemporary(options: options)
        let expectedData = Data([200, 1])
        let expectedSnapshot = DanaGeneratePacket(opCode: 96, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusCancelExtended() {
        let packet = generatePacketBolusCancelExtended()
        let expectedSnapshot = DanaGeneratePacket(opCode: 73, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusGet24Circf() {
        let packet = generatePacketBolusGet24CIRCFArray()
        let expectedSnapshot = DanaGeneratePacket(opCode: 82, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusGetCalculationInformation() {
        let packet = generatePacketBolusGetCalculationInformation()
        let expectedSnapshot = DanaGeneratePacket(opCode: 75, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusGetCircf() {
        let packet = generatePacketBolusGetCIRCFArray()
        let expectedSnapshot = DanaGeneratePacket(opCode: 78, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusGetOption() {
        let packet = generatePacketBolusGetOption()
        let expectedSnapshot = DanaGeneratePacket(opCode: 80, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusGetStepOptionInformation() {
        let packet = generatePacketBolusGetStepInformation()
        let expectedSnapshot = DanaGeneratePacket(opCode: 64, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusSet24Circf_mmolPerL() {
        let options = PacketBolusSet24CIRCFArray(
            unit: 1,
            ic: Array(repeating: 0.5, count: 24),
            isf: Array(repeating: 1, count: 24)
        )
        do {
            let packet = try generatePacketBolusSet24CIRCFArray(options: options)
            let expectedData = Data(
                Array(repeating: [1, 0], count: 24).flatMap { $0 } + Array(repeating: [100, 0], count: 24)
                    .flatMap { $0 }
            )
            let expectedSnapshot = DanaGeneratePacket(opCode: 83, data: expectedData)

            XCTAssertEqual(packet.type, expectedSnapshot.type)
            XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
            XCTAssertEqual(packet.data, expectedSnapshot.data)
        } catch {
            XCTFail()
        }
    }

    func testGenerateBolusSet24Circf() {
        let options = PacketBolusSet24CIRCFArray(
            unit: 0,
            ic: Array(repeating: 0.5, count: 24),
            isf: Array(repeating: 1, count: 24)
        )
        do {
            let packet = try generatePacketBolusSet24CIRCFArray(options: options)
            let expectedData = Data(Array(repeating: [1, 0], count: 48).flatMap { $0 })
            let expectedSnapshot = DanaGeneratePacket(opCode: 83, data: expectedData)

            XCTAssertEqual(packet.type, expectedSnapshot.type)
            XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
            XCTAssertEqual(packet.data, expectedSnapshot.data)
        } catch {
            XCTFail()
        }
    }

    func testGenerateBolusSet24Circf_InvalidInput() {
        let optionsInvalidIc = PacketBolusSet24CIRCFArray(
            unit: 0,
            ic: Array(repeating: 0.5, count: 23),
            isf: Array(repeating: 1, count: 24)
        )
        let optionsInvalidIsf = PacketBolusSet24CIRCFArray(
            unit: 0,
            ic: Array(repeating: 0.5, count: 24),
            isf: Array(repeating: 1, count: 23)
        )

        XCTAssertThrowsError(try generatePacketBolusSet24CIRCFArray(options: optionsInvalidIc))
        XCTAssertThrowsError(try generatePacketBolusSet24CIRCFArray(options: optionsInvalidIsf))
    }

    func testGenerateBolusSetExtended() {
        let options = PacketBolusSetExtended(extendedAmount: 5, extendedDurationInHalfHours: 4)
        let packet = generatePacketBolusSetExtended(options: options)
        let expectedData = Data([5, 0, 4])
        let expectedSnapshot = DanaGeneratePacket(opCode: 71, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusSetOption() {
        let options = PacketBolusSetOption(
            extendedBolusOptionOnOff: 0,
            bolusCalculationOption: 1,
            missedBolusConfig: 1,
            missedBolus01StartHour: 0,
            missedBolus01StartMin: 0,
            missedBolus01EndHour: 0,
            missedBolus01EndMin: 0,
            missedBolus02StartHour: 0,
            missedBolus02StartMin: 0,
            missedBolus02EndHour: 0,
            missedBolus02EndMin: 0,
            missedBolus03StartHour: 0,
            missedBolus03StartMin: 0,
            missedBolus03EndHour: 0,
            missedBolus03EndMin: 0,
            missedBolus04StartHour: 0,
            missedBolus04StartMin: 0,
            missedBolus04EndHour: 0,
            missedBolus04EndMin: 0
        )
        let packet = generatePacketBolusSetOption(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 81, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusStart_Speed12() {
        let options = PacketBolusStart(amount: 5, speed: .speed12)
        let packet = generatePacketBolusStart(options: options)
        let expectedData = Data([244, 1, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 74, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusStart_Speed30() {
        let options = PacketBolusStart(amount: 5, speed: .speed30)
        let packet = generatePacketBolusStart(options: options)
        let expectedData = Data([244, 1, 1])
        let expectedSnapshot = DanaGeneratePacket(opCode: 74, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusStart_Speed60() {
        let options = PacketBolusStart(amount: 5, speed: .speed60)
        let packet = generatePacketBolusStart(options: options)
        let expectedData = Data([244, 1, 2])
        let expectedSnapshot = DanaGeneratePacket(opCode: 74, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateBolusStop() {
        let packet = generatePacketBolusStop()
        let expectedSnapshot = DanaGeneratePacket(opCode: 68, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralAvgBolus() {
        let packet = generatePacketGeneralAvgBolus()
        let expectedSnapshot = DanaGeneratePacket(opCode: 16, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralClearUserTimeChangeFlag() {
        let packet = generatePacketGeneralClearUserTimeChangeFlag()
        let expectedSnapshot = DanaGeneratePacket(opCode: 35, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetDecRatio() {
        let packet = generatePacketGeneralGetPumpDecRatio()
        let expectedSnapshot = DanaGeneratePacket(opCode: 128, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetInitialScreenInformation() {
        let packet = generatePacketGeneralGetInitialScreenInformation()
        let expectedSnapshot = DanaGeneratePacket(opCode: 2, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetPumpCheck() {
        let packet = generatePacketGeneralGetPumpCheck()
        let expectedSnapshot = DanaGeneratePacket(opCode: 33, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetPumpTime() {
        let packet = generatePacketGeneralGetPumpTime()
        let expectedSnapshot = DanaGeneratePacket(opCode: 112, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetPumpTimeWithUtc() {
        let packet = generatePacketGeneralGetPumpTimeUtcWithTimezone()
        let expectedSnapshot = DanaGeneratePacket(opCode: 120, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetShippingInformation() {
        let packet = generatePacketGeneralGetShippingInformation()
        let expectedSnapshot = DanaGeneratePacket(opCode: 32, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetShippingVersion() {
        let packet = generatePacketGeneralGetShippingVersion()
        let expectedSnapshot = DanaGeneratePacket(opCode: 129, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetUserOption() {
        let packet = generatePacketGeneralGetUserOption()
        let expectedSnapshot = DanaGeneratePacket(opCode: 114, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralGetUserTimeChangeFlag() {
        let packet = generatePacketGeneralGetUserTimeChangeFlag()
        let expectedSnapshot = DanaGeneratePacket(opCode: 34, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralKeepConnection() {
        let packet = generatePacketGeneralKeepConnection()
        let expectedSnapshot = DanaGeneratePacket(opCode: 255, data: nil)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralSaveHistory() {
        let options = PacketGeneralSaveHistory(
            historyType: 1,
            historyDate: Date(timeIntervalSince1970: 1_701_774_000),
            historyCode: 1,
            historyValue: 1
        )
        let packet = generatePacketGeneralSaveHistory(options: options)
        let expectedData = Data([1, 23, 12, 5, 11, 0, 0, 1, 1, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 224, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralSetHistoryUploadMode_TurnOff() {
        let options = PacketGeneralSetHistoryUploadMode(mode: 0)
        let packet = generatePacketGeneralSetHistoryUploadMode(options: options)
        let expectedData = Data([0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 37, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralSetHistoryUploadMode_TurnOn() {
        let options = PacketGeneralSetHistoryUploadMode(mode: 1)
        let packet = generatePacketGeneralSetHistoryUploadMode(options: options)
        let expectedData = Data([1])
        let expectedSnapshot = DanaGeneratePacket(opCode: 37, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralSetPumpTime() {
        // 2023-12-05T11:00:00.000 UTC
        let options = PacketGeneralSetPumpTime(time: Date(timeIntervalSince1970: 1_701_774_000))
        let packet = generatePacketGeneralSetPumpTime(options: options)
        let expectedData = Data([23, 12, 5, 11, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 113, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralSetPumpTimeWithTimezone() {
        let options = PacketGeneralSetPumpTimeUtcWithTimezone(time: Date(timeIntervalSince1970: 1_701_774_000), zoneOffset: 1)
        let packet = generatePacketGeneralSetPumpTimeUtcWithTimezone(options: options)
        let expectedData = Data([23, 12, 5, 11, 0, 0, 1])
        let expectedSnapshot = DanaGeneratePacket(opCode: 121, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateGeneralSetUserOption() {
        let options = PacketGeneralSetUserOption(
            isTimeDisplay24H: true,
            isButtonScrollOnOff: true,
            beepAndAlarm: 0,
            lcdOnTimeInSec: 10,
            backlightOnTimeInSec: 10,
            selectedLanguage: 1,
            units: 1,
            shutdownHour: 0,
            lowReservoirRate: 20,
            cannulaVolume: 250,
            refillAmount: 7,
            targetBg: 55
        )
        let packet = generatePacketGeneralSetUserOption(options: options)
        let expectedData = Data([0, 1, 0, 10, 10, 1, 1, 0, 20, 250, 0, 7, 0, 55, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 115, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryAlarmFromDate() {
        let options = PacketHistoryBase(from: Date(timeIntervalSince1970: 1_701_774_000))
        let packet = generatePacketHistoryAlarm(options: options)
        let expectedData = Data([23, 12, 5, 11, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 25, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryAlarm() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryAlarm(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 25, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryAll() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryAll(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 31, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryBasal() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryBasal(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 26, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryBloodGlucose() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryBloodGlucose(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 21, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryBolus() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryBolus(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 17, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryCarbohydrates() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryCarbohydrates(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 22, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryDaily() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryDaily(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 18, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryPrime() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryPrime(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 19, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryRefill() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryRefill(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 20, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistorySuspend() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistorySuspend(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 24, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateHistoryTemporary() {
        let options = PacketHistoryBase(from: nil)
        let packet = generatePacketHistoryTemporary(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 23, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateLoopHistoryEventsFromDateInUTC() {
        let options = PacketLoopHistoryEvents(from: Date(timeIntervalSince1970: 1_701_774_000))
        let packet = generatePacketLoopHistoryEvents(options: options)
        let expectedData = Data([23, 12, 5, 11, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 194, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateLoopHistoryEvents() {
        let options = PacketLoopHistoryEvents(from: nil)
        let packet = generatePacketLoopHistoryEvents(options: options)
        let expectedData = Data([0, 1, 1, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 194, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateLoopSetHistoryEvent() {
        let options = PacketLoopSetEventHistory(
            packetType: LoopHistoryEvents.carbs,
            time: Date(timeIntervalSince1970: 1_701_774_000),
            param1: 0,
            param2: 0
        )
        let packet = generatePacketLoopSetEventHistory(options: options)
        let expectedData = Data([14, 23, 12, 5, 11, 0, 0, 0, 0, 0, 0])
        let expectedSnapshot = DanaGeneratePacket(opCode: 195, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateLoopSetTemporaryBasal() {
        let options = PacketLoopSetTemporaryBasal(percent: 200, duration: .min30)
        let packet = generatePacketLoopSetTemporaryBasal(options: options)
        let expectedData = Data([200, 0, 160])
        let expectedSnapshot = DanaGeneratePacket(opCode: 193, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }

    func testGenerateLoopSetTemporaryBasalPercentGreaterThan500() {
        let options = PacketLoopSetTemporaryBasal(percent: 750, duration: .min15)
        let packet = generatePacketLoopSetTemporaryBasal(options: options)
        let expectedData = Data([244, 1, 150])
        let expectedSnapshot = DanaGeneratePacket(opCode: 193, data: expectedData)

        XCTAssertEqual(packet.type, expectedSnapshot.type)
        XCTAssertEqual(packet.opCode, expectedSnapshot.opCode)
        XCTAssertEqual(packet.data, expectedSnapshot.data)
    }
}
