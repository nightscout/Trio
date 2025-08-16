//
//  PodInfoTests.swift
//  OmniKitTests
//
//  Created by Eelke Jager on 18/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

import XCTest
@testable import OmniKit

class PodInfoTests: XCTestCase {
    func testFullMessage() {
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0d 00 0000 00 00ab 6a 0384 03ff 0386 00 00 28 57 08 030d
        do {
            // Decode
            let infoResponse = try PodInfoResponse(encodedData: Data(hexadecimalString: "0216020d0000000000ab6a038403ff03860000285708030d0000")!)
            XCTAssertEqual(infoResponse.podInfoResponseSubType, .detailedStatus)
            let faultEvent = infoResponse.podInfo as! DetailedStatus
            XCTAssertEqual(faultEvent.podInfoType, .detailedStatus)
            XCTAssertEqual(faultEvent.podProgressStatus, .faultEventOccurred)
            XCTAssertEqual(faultEvent.deliveryStatus, .suspended)
            XCTAssertEqual(faultEvent.bolusNotDelivered, 0)
            XCTAssertEqual(faultEvent.lastProgrammingMessageSeqNum, 0)
            XCTAssertEqual(faultEvent.totalInsulinDelivered, 0xab * Pod.pulseSize)
            XCTAssertEqual(faultEvent.totalInsulinDelivered, 8.55)
            XCTAssertEqual(faultEvent.faultEventCode.faultType, .occlusionCheckAboveThreshold)
            XCTAssertEqual(faultEvent.faultEventTimeSinceActivation, 0x384 * 60)
            XCTAssertEqual(faultEvent.faultEventTimeSinceActivation, 54000)
            XCTAssertEqual(faultEvent.reservoirLevel, Pod.reservoirLevelAboveThresholdMagicNumber, accuracy: 0.01)
            XCTAssertEqual(faultEvent.timeActive, 0x386 * 60)
            XCTAssertEqual(faultEvent.timeActive, 54120)
            XCTAssertEqual(faultEvent.unacknowledgedAlerts, AlertSet(rawValue: 0))
            XCTAssertEqual(faultEvent.faultAccessingTables, false)
            XCTAssertEqual(faultEvent.podProgressStatus, .faultEventOccurred)
            XCTAssertEqual(faultEvent.errorEventInfo?.insulinStateTableCorruption, false)
            XCTAssertEqual(faultEvent.errorEventInfo?.occlusionType, 1)
            XCTAssertEqual(faultEvent.errorEventInfo?.immediateBolusInProgress, false)
            XCTAssertEqual(faultEvent.errorEventInfo?.podProgressStatus, .aboveFiftyUnits)
            XCTAssertEqual(faultEvent.receiverLowGain, 0b01)
            XCTAssertEqual(faultEvent.radioRSSI, 0x17)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoTriggeredAlertsEmpty() {
        // 02DATAOFF 0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
        // 02 13 // 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV
        // 02 13 // 01 0000 0000 0000 0000 0000 0000 0000 0000 0000
        do {
            // Decode
            let decoded = try PodInfoTriggeredAlerts(encodedData: Data(hexadecimalString: "01000000000000000000000000000000000000")!)
            XCTAssertEqual(.triggeredAlerts, decoded.podInfoType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoTriggeredAlertsSuspendStillActive() {
        // 02DATAOFF 0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
        // 02 13 // 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV
        // 02 13 // 01 0000 0000 0000 0000 0000 0000 0bd7 0c40 0000 // real alert value after 2 hour suspend
        do {
            // Decode
            let decoded = try PodInfoTriggeredAlerts(encodedData: Data(hexadecimalString: "010000000000000000000000000bd70c400000")!)
            XCTAssertEqual(.triggeredAlerts, decoded.podInfoType)
            XCTAssertEqual("50h31m", decoded.alertActivations[5].timeIntervalStr)
            XCTAssertEqual("52h16m", decoded.alertActivations[6].timeIntervalStr)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoTriggeredAlertsReplacePodAfter3DaysAnd8Hours() {
        // 02DATAOFF 0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
        // 02 13 // 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV
        // 02 13 // 01 0000 0000 0000 0000 0000 0000 0000 0000 10e1
        do {
            let decoded = try PodInfoTriggeredAlerts(encodedData: Data(hexadecimalString: "010000000000000000000000000000000010e1")!)
            XCTAssertEqual(.triggeredAlerts, decoded.podInfoType)
            XCTAssertEqual("72h1m", decoded.alertActivations[7].timeIntervalStr)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoTriggeredAlertsReplacePodAfterReservoirEmpty() {
        // 02DATAOFF 0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
        // 02 13 // 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV
        // 02 13 // 01 0000 0000 0000 1285 0000 11c7 0000 0000 119c
        do {
            let decoded = try PodInfoTriggeredAlerts(encodedData: Data(hexadecimalString: "010000000000001285000011c700000000119c")!)
            XCTAssertEqual(.triggeredAlerts, decoded.podInfoType)
            XCTAssertEqual("79h1m", decoded.alertActivations[2].timeIntervalStr)
            XCTAssertEqual("75h51m", decoded.alertActivations[4].timeIntervalStr)
            XCTAssertEqual("75h8m", decoded.alertActivations[7].timeIntervalStr)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoTriggeredAlertsReplacePod() {
        // 02DATAOFF 0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
        // 02 13 // 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV
        // 02 13 // 01 0000 0000 0000 1284 0000 0000 0000 0000 10e0
        do {
            let decoded = try PodInfoTriggeredAlerts(encodedData: Data(hexadecimalString: "010000000000001284000000000000000010e0")!)
            XCTAssertEqual(.triggeredAlerts, decoded.podInfoType)
            XCTAssertEqual("79h", decoded.alertActivations[2].timeIntervalStr)
            XCTAssertEqual("72h", decoded.alertActivations[7].timeIntervalStr)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoNoFaultAlerts() {
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 08 01 0000 0a 0038 00 0000 03ff 0087 00 00 00 95 ff 0000
        do {
            // Decode
            let decoded = try DetailedStatus(encodedData: Data(hexadecimalString: "02080100000a003800000003ff008700000095ff0000")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
            XCTAssertEqual(.aboveFiftyUnits, decoded.podProgressStatus)
            XCTAssertEqual(.scheduledBasal, decoded.deliveryStatus)
            XCTAssertEqual(0000, decoded.bolusNotDelivered)
            XCTAssertEqual(0x0a, decoded.lastProgrammingMessageSeqNum)
            XCTAssertEqual(.noFaults, decoded.faultEventCode.faultType)
            XCTAssertEqual(TimeInterval(minutes: 0x0000), decoded.faultEventTimeSinceActivation)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, decoded.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(8100, decoded.timeActive)
            XCTAssertEqual(TimeInterval(minutes: 0x0087), decoded.timeActive)
            XCTAssertEqual("2h15m", decoded.timeActive.timeIntervalStr)
            XCTAssertEqual(0, decoded.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(false, decoded.faultAccessingTables)
            XCTAssertNil(decoded.errorEventInfo)
            XCTAssertEqual(0b10, decoded.receiverLowGain)
            XCTAssertEqual(0x15, decoded.radioRSSI)
            XCTAssertNil(decoded.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPodInfoDeliveryErrorDuringPriming() {
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0f 00 0000 09 0034 5c 0001 03ff 0001 00 00 05 ae 05 6029
        do {
            // Decode
            let decoded = try DetailedStatus(encodedData: Data(hexadecimalString: "020f0000000900345c000103ff0001000005ae056029")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
            XCTAssertEqual(.inactive, decoded.podProgressStatus)
            XCTAssertEqual(.suspended, decoded.deliveryStatus)
            XCTAssertEqual(0000, decoded.bolusNotDelivered)
            XCTAssertEqual(9, decoded.lastProgrammingMessageSeqNum)
            XCTAssertEqual(.primeOpenCountTooLow, decoded.faultEventCode.faultType)
            XCTAssertEqual(TimeInterval(minutes: 0x0001), decoded.faultEventTimeSinceActivation)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, decoded.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 0x0001), decoded.timeActive)
            XCTAssertEqual(60, decoded.timeActive)
            XCTAssertEqual(00, decoded.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(false, decoded.faultAccessingTables)
            XCTAssertEqual(false, decoded.errorEventInfo?.insulinStateTableCorruption)
            XCTAssertEqual(0, decoded.errorEventInfo?.occlusionType)
            XCTAssertEqual(false, decoded.errorEventInfo?.immediateBolusInProgress)
            XCTAssertEqual(.primingCompleted, decoded.errorEventInfo?.podProgressStatus)
            XCTAssertEqual(0b10, decoded.receiverLowGain)
            XCTAssertEqual(0x2e, decoded.radioRSSI)
            XCTAssertEqual(.primingCompleted, decoded.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPodInfoDuringPriming() {
        // Needle cap accidentally removed before priming started leaking and gave error:
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0d 00 0000 06 0000 8f 0000 03ff 0000 00 00 03 a2 03 86a0
        do {
            // Decode
            let decoded = try DetailedStatus(encodedData: Data(hexadecimalString: "020d0000000600008f000003ff0000000003a20386a0")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
            XCTAssertEqual(.faultEventOccurred, decoded.podProgressStatus)
            XCTAssertEqual(.suspended, decoded.deliveryStatus)
            XCTAssertEqual(0, decoded.bolusNotDelivered, accuracy: 0.01)
            XCTAssertEqual(6, decoded.lastProgrammingMessageSeqNum)
            XCTAssertEqual(.command1AParseUnexpectedFailed, decoded.faultEventCode.faultType)
            XCTAssertEqual(TimeInterval(minutes: 0x0000), decoded.faultEventTimeSinceActivation)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, decoded.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 0x0000), decoded.timeActive)
            XCTAssertEqual(0, decoded.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(false, decoded.faultAccessingTables)
            XCTAssertEqual(false, decoded.errorEventInfo?.insulinStateTableCorruption)
            XCTAssertEqual(0, decoded.errorEventInfo?.occlusionType)
            XCTAssertEqual(PodProgressStatus.pairingCompleted, decoded.errorEventInfo?.podProgressStatus)
            XCTAssertEqual(0b10, decoded.receiverLowGain)
            XCTAssertEqual(0x22, decoded.radioRSSI)
            XCTAssertEqual(.pairingCompleted, decoded.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPodInfoFaultEventErrorShuttingDown() {
        // Failed Pod after 42+ hours of live use shortly after installing a buggy version of Loop.
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0d 00 0000 04 07f2 86 09ff 03ff 0a02 00 00 08 23 08 0000
        do {
            // Decode
            let decoded = try DetailedStatus(encodedData: Data(hexadecimalString: "020d0000000407f28609ff03ff0a0200000823080000")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
            XCTAssertEqual(.faultEventOccurred, decoded.podProgressStatus)
            XCTAssertEqual(.suspended, decoded.deliveryStatus)
            XCTAssertEqual(0, decoded.bolusNotDelivered)
            XCTAssertEqual(4, decoded.lastProgrammingMessageSeqNum)
            XCTAssertEqual(101.7, decoded.totalInsulinDelivered, accuracy: 0.01)
            XCTAssertEqual(.basalOverInfusionPulse, decoded.faultEventCode.faultType)
            XCTAssertEqual(0, decoded.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(TimeInterval(minutes: 0x09ff), decoded.faultEventTimeSinceActivation)
            XCTAssertEqual("42h39m", decoded.faultEventTimeSinceActivation?.timeIntervalStr)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, decoded.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 0x0a02), decoded.timeActive)
            XCTAssertEqual(false, decoded.faultAccessingTables)
            XCTAssertEqual(false, decoded.errorEventInfo?.insulinStateTableCorruption)
            XCTAssertEqual(0, decoded.errorEventInfo?.occlusionType)
            XCTAssertEqual(false, decoded.errorEventInfo?.immediateBolusInProgress)
            XCTAssertEqual(.aboveFiftyUnits, decoded.errorEventInfo?.podProgressStatus)
            XCTAssertEqual(0b00, decoded.receiverLowGain)
            XCTAssertEqual(0x23, decoded.radioRSSI)
            XCTAssertEqual(.aboveFiftyUnits, decoded.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoFaultEventCheckAboveThreshold() {
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0d 00 0000 04 07eb 6a 0e0c 03ff 0e14 00 00 28 17 08 0000
        do {
            // Decode
            let decoded = try DetailedStatus(encodedData: Data(hexadecimalString: "020d0000000407eb6a0e0c03ff0e1400002817080000")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
            XCTAssertEqual(.faultEventOccurred, decoded.podProgressStatus)
            XCTAssertEqual(.suspended, decoded.deliveryStatus)
            XCTAssertEqual(0, decoded.bolusNotDelivered)
            XCTAssertEqual(4, decoded.lastProgrammingMessageSeqNum)
            XCTAssertEqual(101.35, decoded.totalInsulinDelivered, accuracy: 0.01)
            XCTAssertEqual(.occlusionCheckAboveThreshold, decoded.faultEventCode.faultType)
            XCTAssertEqual(0, decoded.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(TimeInterval(minutes: 0x0e0c), decoded.faultEventTimeSinceActivation)
            XCTAssertEqual("59h56m", decoded.faultEventTimeSinceActivation?.timeIntervalStr)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, decoded.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 0x0e14), decoded.timeActive)
            XCTAssertEqual(false, decoded.faultAccessingTables)
            XCTAssertEqual(false, decoded.errorEventInfo?.insulinStateTableCorruption)
            XCTAssertEqual(1, decoded.errorEventInfo?.occlusionType)
            XCTAssertEqual(false, decoded.errorEventInfo?.immediateBolusInProgress)
            XCTAssertEqual(.aboveFiftyUnits, decoded.errorEventInfo?.podProgressStatus)
            XCTAssertEqual(0b00, decoded.receiverLowGain)
            XCTAssertEqual(0x17, decoded.radioRSSI)
            XCTAssertEqual(.aboveFiftyUnits, decoded.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoFaultEventBolusNotDelivered() {
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0f 00 0001 02 00ec 6a 0268 03ff 026b 00 00 28 a7 08 2023
        do {
            // Decode
            let decoded = try DetailedStatus(encodedData: Data(hexadecimalString: "020f0000010200ec6a026803ff026b000028a7082023")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
            XCTAssertEqual(.inactive, decoded.podProgressStatus)
            XCTAssertEqual(.suspended, decoded.deliveryStatus)
            XCTAssertEqual(0.05, decoded.bolusNotDelivered)
            XCTAssertEqual(2, decoded.lastProgrammingMessageSeqNum)
            XCTAssertEqual(11.8, decoded.totalInsulinDelivered, accuracy: 0.01)
            XCTAssertEqual(.occlusionCheckAboveThreshold, decoded.faultEventCode.faultType)
            XCTAssertEqual(0, decoded.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(TimeInterval(minutes: 0x0268), decoded.faultEventTimeSinceActivation)
            XCTAssertEqual("10h16m", decoded.faultEventTimeSinceActivation?.timeIntervalStr)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, decoded.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 0x026b), decoded.timeActive)
            XCTAssertEqual(false, decoded.faultAccessingTables)
            XCTAssertEqual(false, decoded.errorEventInfo?.insulinStateTableCorruption)
            XCTAssertEqual(1, decoded.errorEventInfo?.occlusionType)
            XCTAssertEqual(false, decoded.errorEventInfo?.immediateBolusInProgress)
            XCTAssertEqual(.aboveFiftyUnits, decoded.errorEventInfo?.podProgressStatus)
            XCTAssertEqual(0b10, decoded.receiverLowGain)
            XCTAssertEqual(0x27, decoded.radioRSSI)
            XCTAssertEqual(.aboveFiftyUnits, decoded.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoFaultEventResetDueToLowVoltageDetect() {
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0D 00 0000 00 0000 12 FFFF 03FF 0016 00 00 87 9A 07 0000
        do {
            // Decode
            let decoded = try DetailedStatus(encodedData: Data(hexadecimalString: "020D00000000000012FFFF03FF00160000879A070000")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
            XCTAssertEqual(.faultEventOccurred, decoded.podProgressStatus)
            XCTAssertEqual(.suspended, decoded.deliveryStatus)
            XCTAssertEqual(0.00, decoded.bolusNotDelivered)
            XCTAssertEqual(0, decoded.lastProgrammingMessageSeqNum)
            XCTAssertEqual(0.00, decoded.totalInsulinDelivered, accuracy: 0.01)
            XCTAssertEqual(.resetDueToLVD, decoded.faultEventCode.faultType)
            XCTAssertNil(decoded.faultEventTimeSinceActivation)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, decoded.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 0x16), decoded.timeActive)
            XCTAssertEqual(0, decoded.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(false, decoded.faultAccessingTables)
            XCTAssertEqual(true, decoded.errorEventInfo?.insulinStateTableCorruption)
            XCTAssertEqual(0, decoded.errorEventInfo?.occlusionType)
            XCTAssertEqual(false, decoded.errorEventInfo?.immediateBolusInProgress)
            XCTAssertEqual(.insertingCannula, decoded.errorEventInfo?.podProgressStatus)
            XCTAssertEqual(0b10, decoded.receiverLowGain)
            XCTAssertEqual(0x1A, decoded.radioRSSI)
            XCTAssertEqual(.insertingCannula, decoded.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPodInfoPulseLogPlusPartial() {
        // 02DATAOFF 0  1  2 3  4 5  6  7  8
        // 02 LL // 03 PP QQQQ SSSS 04 3c XXXXXXXX ...
        // 02 e4 // 03 00 0000 0003 04 3c 00622a80 01612980 00612480 01602680 00611f00 01601a00 00611f00 01602600 00602000 01602600 00602200 01612700 00602000 01602500 00602000 01612500 00612180 01612680 00612080 01612780 00612080 01602680 00612080 01602580 00612080 05612500 08602000 0d612600 10602200 15602800 18612100 1d602800 20602100 25612700 28612100 2d602800 30612200 35602800 38602400 3d602700 40612400 45612c80 48612680 4d602d80 00602780 05632b80 08612680 0d602c80 10612580 15602d80 18602300 1d612100 20612200 25612900 28602300
        do {
            let decoded = try PodInfoPulseLogPlus(encodedData: Data(hexadecimalString: "030000000003043c00622a8001612980006124800160268000611f0001601a0000611f0001602600006020000160260000602200016127000060200001602500006020000161250000612180016126800061208001612780006120800160268000612080016025800061208005612500086020000d6126001060220015602800186121001d6028002060210025612700286121002d6028003061220035602800386024003d6027004061240045612c80486126804d602d800060278005632b80086126800d602c801061258015602d80186023001d612100206122002561290028602300")!)
            XCTAssertEqual(.pulseLogPlus, decoded.podInfoType)
            XCTAssertEqual(.noFaults, decoded.faultEventCode.faultType)
            XCTAssertEqual(0000*60, decoded.timeFaultEvent)
            XCTAssertEqual(0003*60, decoded.timeActivation)
            XCTAssertEqual(4, decoded.entrySize)
            XCTAssertEqual(0x3c, decoded.maxEntries)
            XCTAssertEqual(0x00622a80, decoded.pulseLog[0])
            XCTAssertEqual(0x01602600, decoded.pulseLog[9])
            XCTAssertEqual(0x01612780, decoded.pulseLog[19])
            XCTAssertEqual(0x15602800, decoded.pulseLog[29])
            XCTAssertEqual(0x3d602700, decoded.pulseLog[39])
            XCTAssertEqual(0x15602d80, decoded.pulseLog[49])
            XCTAssertEqual(0x28602300, decoded.pulseLog[54])
            XCTAssertEqual(55, decoded.nEntries) // a calculated value that is not directly in raw hex data
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPodInfoPulseLogPlus() {
        // 02DATAOFF 0  1  2 3  4 5  6  7  8
        // 02 LL // 03 PP QQQQ SSSS 04 3c XXXXXXXX ...
        // 02 f8 // 03 00 0000 0075 04 3c 54402600 59402d80 5c412480 61402d80 00412380 05402d80 08402780 0d402c80 10412480 15412b80 18412400 1d402800 20402400 25412c00 28412500 2d412b00 30402700 35412d00 38402600 3d412c00 40412500 45402c00 48402400 4d412c00 50412400 55412e00 58412680 5d402f80 60402680 01402f80 04402680 09412e80 0c402580 11402e80 14402780 19402e00 1c402400 21412d00 24402600 29412f00 2c412600 31643000 34622600 39623000 3c622600 41622f00 44622600 49622e00 4c632600 51632d00 54602800 59413080 5c412780 61403180 00402880 05413080 08402780 0d413180 10412680 15412f80
        do {
            let decoded = try PodInfoPulseLogPlus(encodedData: Data(hexadecimalString: "030000000075043c5440260059402d805c41248061402d800041238005402d80084027800d402c801041248015412b80184124001d4028002040240025412c00284125002d412b003040270035412d00384026003d412c004041250045402c00484024004d412c005041240055412e00584126805d402f806040268001402f800440268009412e800c40258011402e801440278019402e001c40240021412d002440260029412f002c4126003164300034622600396230003c62260041622f004462260049622e004c63260051632d0054602800594130805c412780614031800040288005413080084027800d4131801041268015412f80")!)
            XCTAssertEqual(.pulseLogPlus, decoded.podInfoType)
            XCTAssertEqual(.noFaults, decoded.faultEventCode.faultType)
            XCTAssertEqual(TimeInterval(minutes: 0x0000), decoded.timeFaultEvent)
            XCTAssertEqual(TimeInterval(minutes: 0x0075), decoded.timeActivation)
            XCTAssertEqual(4, decoded.entrySize)
            XCTAssertEqual(0x3c, decoded.maxEntries)
            XCTAssertEqual(0x54402600, decoded.pulseLog[0])
            XCTAssertEqual(0x15412b80, decoded.pulseLog[9])
            XCTAssertEqual(0x3d412c00, decoded.pulseLog[19])
            XCTAssertEqual(0x01402f80, decoded.pulseLog[29])
            XCTAssertEqual(0x29412f00, decoded.pulseLog[39])
            XCTAssertEqual(0x51632d00, decoded.pulseLog[49])
            XCTAssertEqual(0x15412f80, decoded.pulseLog[59])
            XCTAssertEqual(0x3c, decoded.nEntries) // a calculated value
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoActivationTime() {
        // 02DATAOFF 0  1  2 3  4 5 6 7  8 91011 1213141516
        // 02 11 // 05 PP QQQQ 00000000 00000000 MMDDYYHHMM
        // 02 11 // 05 92 0001 00000000 00000000 091912170e
        // 09-25-18 23:14 int values for datetime
        do {                                            
            // Decode
            let decoded = try PodInfoActivationTime(encodedData: Data(hexadecimalString: "059200010000000000000000091912170e")!)
            XCTAssertEqual(.activationTime, decoded.podInfoType)
            XCTAssertEqual(.tempPulseChanInactive, decoded.faultEventCode.faultType)
            XCTAssertEqual(TimeInterval(minutes: 0x0001), decoded.faultTime)
            XCTAssertEqual(18, decoded.year)
            XCTAssertEqual(09, decoded.month)
            XCTAssertEqual(25, decoded.day)
            XCTAssertEqual(23, decoded.hour)
            XCTAssertEqual(14, decoded.minute)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testPodInfoPulseLogRecent() {
       //02 cb 50 0086 34212e00 39203100 3c212d00 41203000 44202c00 49212e00 4c212b00 51202f00 54212c00 59203080 5c202d80 61203080 00212e80 05213180 08202f80 0d203280 10202f80 15213180 18202f80 1d213180 20202e80 25213300 28203200 2d213500 30213100 35213400 38213100 3d203500 40203100 45213300 48203000 4d213200 50212f00 55203300 58203080 5d213280 60202f80 01203080 04202c80 09213180 0c213080 11213280 14203180 19213380 1c203180 21203280 24213200 29203500 2c213100 31213400"
        do {
            // Decode
            let decoded = try PodInfoPulseLogRecent(encodedData: Data(hexadecimalString: "50008634212e00392031003c212d004120300044202c0049212e004c212b0051202f0054212c00592030805c202d806120308000212e800521318008202f800d20328010202f801521318018202f801d21318020202e8025213300282032002d2135003021310035213400382131003d2035004020310045213300482030004d21320050212f0055203300582030805d21328060202f800120308004202c80092131800c2130801121328014203180192133801c2031802120328024213200292035002c21310031213400")!)
            XCTAssertEqual(.pulseLogRecent, decoded.podInfoType)
            XCTAssertEqual(134, decoded.indexLastEntry)
            XCTAssertEqual(0x34212e00, decoded.pulseLog[0])
            XCTAssertEqual(0x59203080, decoded.pulseLog[9])
            XCTAssertEqual(0x1d213180, decoded.pulseLog[19])
            XCTAssertEqual(0x45213300, decoded.pulseLog[29])
            XCTAssertEqual(0x09213180, decoded.pulseLog[39])
            XCTAssertEqual(0x31213400, decoded.pulseLog[49])
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPodInfoPulseLogPrevious() {
        //02 cb 51 0032 14602500 19612800 1c612400 21612800 24612500 29612900 2c602600 31602a00 34602600 39612a80 3c612680 41602c80 00602780 05632880 08602580 0d612880 10612580 15612780 18602380 1d602680 20612280 25602700 28612400 2d212800 30202700 35202a00 38202700 3d202a00 40202900 45202c00 48202a00 4d212c00 50212900 55212c00 58212980 5d202b80 60202880 01202d80 04212a80 09202d80 0c212980 11212a80 14212980 1921801c 212a8021 212c8024 202c0029 212f002c 212d0031 20310082
        do {
            // Decode
            let decoded = try PodInfoPulseLogPrevious(encodedData: Data(hexadecimalString: "51003214602500196128001c6124002161280024612500296129002c60260031602a003460260039612a803c61268041602c800060278005632880086025800d6128801061258015612780186023801d6026802061228025602700286124002d2128003020270035202a00382027003d202a004020290045202c0048202a004d212c005021290055212c00582129805d202b806020288001202d8004212a8009202d800c21298011212a80142129801921801c212a8021212c8024202c0029212f002c212d003120310082")!)
            XCTAssertEqual(.pulseLogPrevious, decoded.podInfoType)
            XCTAssertEqual(50, decoded.nEntries)
            XCTAssertEqual(0x14602500, decoded.pulseLog[0])
            XCTAssertEqual(0x39612a80, decoded.pulseLog[9])
            XCTAssertEqual(0x1d602680, decoded.pulseLog[19])
            XCTAssertEqual(0x45202c00, decoded.pulseLog[29])
            XCTAssertEqual(0x09202d80, decoded.pulseLog[39])
            XCTAssertEqual(0x20310082, decoded.pulseLog[49])
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPodFault12() {
        // 02DATAOFF 0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
        // 02 16 // 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY
        // 02 16 // 02 0d 00 0000 00 0000 12 ffff 03ff 0000 00 00 87 92 07 0000
        do {
            // Decode
            let faultEvent = try DetailedStatus(encodedData: Data(hexadecimalString: "020d00000000000012ffff03ff000000008792070000")!)
            XCTAssertEqual(.detailedStatus, faultEvent.podInfoType)
            XCTAssertEqual(.faultEventOccurred, faultEvent.podProgressStatus)
            XCTAssertEqual(.suspended, faultEvent.deliveryStatus)
            XCTAssertEqual(0.00, faultEvent.bolusNotDelivered)
            XCTAssertEqual(0, faultEvent.lastProgrammingMessageSeqNum)
            XCTAssertEqual(0.00, faultEvent.totalInsulinDelivered, accuracy: 0.01)
            XCTAssertEqual(.resetDueToLVD, faultEvent.faultEventCode.faultType)
            XCTAssertNil(faultEvent.faultEventTimeSinceActivation)
            XCTAssertEqual(Pod.reservoirLevelAboveThresholdMagicNumber, faultEvent.reservoirLevel, accuracy: 0.01)
            XCTAssertEqual(TimeInterval(minutes: 0x0000), faultEvent.timeActive)
            XCTAssertEqual(0, faultEvent.unacknowledgedAlerts.rawValue)
            XCTAssertEqual(false, faultEvent.faultAccessingTables)
            XCTAssertEqual(true, faultEvent.errorEventInfo?.insulinStateTableCorruption)
            XCTAssertEqual(0, faultEvent.errorEventInfo?.occlusionType)
            XCTAssertEqual(false, faultEvent.errorEventInfo?.immediateBolusInProgress)
            XCTAssertEqual(.insertingCannula, faultEvent.errorEventInfo?.podProgressStatus)
            XCTAssertEqual(0b10, faultEvent.receiverLowGain)
            XCTAssertEqual(0x12, faultEvent.radioRSSI)
            XCTAssertEqual(.insertingCannula, faultEvent.previousPodProgressStatus)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
}
