//
//  G7GlucoseMessageTests.swift
//  CGMBLEKitTests
//
//  Created by Pete Schwamb on 9/25/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import G7SensorKit

final class G7GlucoseMessageTests: XCTestCase {

    func testG7MessageData() {
        let data = Data(hexadecimalString: "4e00c35501002601000106008a00060187000f")!
        let message = G7GlucoseMessage(data: data)!

        XCTAssertEqual(138, message.glucose)
        XCTAssertEqual(87485, message.glucoseTimestamp)
        XCTAssert(!message.glucoseIsDisplayOnly)
    }

    func testG7MessageDataWithCalibration() {
        let data = Data(hexadecimalString: "4e000ec10d00c00b00010000680006fe63001f")!
        let message = G7GlucoseMessage(data: data)!

        XCTAssertEqual(104, message.glucose)
        XCTAssertEqual(901390, message.glucoseTimestamp)
        XCTAssert(message.glucoseIsDisplayOnly)
    }

    func testG7MessageDataLifecycle() {
        let startupMessagesHex = [
            "4e00b6000000010000006600ffff017fffff00", // 0
            "4e00cd000000030000010500ffff027fffff01", // 1
            "4e00f90100000400000105009100027effff02", // 2
            "4e00250300000500000105007d00027effff02", // 3
            "4e0051040000060000010500650002dfffff02", // 4
            "4e007d0500000700000105004e0002e7ffff02", // 5
            "4e00ab060000080000010700540006f5ffff0e", // 6
            "4e00d507000009000001050061000601ffff0e", // 7
            "4e004d440e00d40b0001d46b650018036a000e", // 8
        ]
        let messages = startupMessagesHex.map { G7GlucoseMessage(data: Data(hexadecimalString: $0)!)! }

        XCTAssertNil(messages[0].glucose)
        XCTAssertNil(messages[1].glucose)
        XCTAssertEqual(145, messages[2].glucose)

        XCTAssertEqual(.known(.stopped), messages[0].algorithmState)
        XCTAssertEqual(.known(.warmup), messages[1].algorithmState)
        XCTAssertEqual(.known(.warmup), messages[2].algorithmState)
        XCTAssertEqual(.known(.warmup), messages[3].algorithmState)
        XCTAssertEqual(.known(.warmup), messages[4].algorithmState)
        XCTAssertEqual(.known(.warmup), messages[5].algorithmState)
        XCTAssertEqual(.known(.ok), messages[6].algorithmState)
        XCTAssertEqual(.known(.ok), messages[7].algorithmState)
        XCTAssertEqual(.known(.expired), messages[8].algorithmState)

        XCTAssertEqual(1, messages[0].sequence)
        XCTAssertEqual(3, messages[1].sequence)
        XCTAssertEqual(4, messages[2].sequence)
        XCTAssertEqual(5, messages[3].sequence)
        XCTAssertEqual(6, messages[4].sequence)
        XCTAssertEqual(7, messages[5].sequence)
        XCTAssertEqual(8, messages[6].sequence)
        XCTAssertEqual(9, messages[7].sequence)
        XCTAssertEqual(3028, messages[8].sequence)


        XCTAssertEqual(80, messages[0].glucoseTimestamp)
        XCTAssertEqual(200, messages[1].glucoseTimestamp)
        XCTAssertEqual(500, messages[2].glucoseTimestamp)
        XCTAssertEqual(800, messages[3].glucoseTimestamp)
        XCTAssertEqual(1100, messages[4].glucoseTimestamp)
        XCTAssertEqual(1400, messages[5].glucoseTimestamp)
        XCTAssertEqual(1700, messages[6].glucoseTimestamp)
        XCTAssertEqual(2000, messages[7].glucoseTimestamp)
        XCTAssertEqual(907385, messages[8].glucoseTimestamp)
    }

    func testG7MessageDataDetails() {
        //  0  1  2 3 4 5  6 7  8  9 10 11 1213 14 15 16 17 18
        //       TTTTTTTT SQSQ       AGAG BGBG SS          C
        // 4e 00 a89c0000 8800 00 01 0400 8d00 06 03 8a 00 0f

        //2022-09-12 09:18:06.821253 readEGV(txTime=40104,seq=136,session=1,age=4,value=141,pred=138,algo=6,subAlgo=15,rate=3)
        let data = Data(hexadecimalString: "4e00a89c00008800000104008d0006038a000f")!
        let message = G7GlucoseMessage(data: data)!

        XCTAssertEqual(141, message.glucose)
        XCTAssertEqual(40100, message.glucoseTimestamp)
        XCTAssertEqual(136, message.sequence)
        XCTAssertEqual(4, message.age)
        XCTAssertEqual(138, message.predicted)
        XCTAssertEqual(0.3, message.trend)
        XCTAssertEqual(.known(.ok), message.algorithmState)

        XCTAssert(!message.glucoseIsDisplayOnly)
    }

    func testG7MessageDataNegativeRate() {
        let data = Data(hexadecimalString: "4e00c6cc0d00ca0b00010500610006fe5b000f")!
        let message = G7GlucoseMessage(data: data)!
        XCTAssertEqual(-0.2, message.trend)
    }

    func testG7MessageDataMissingRate() {
        let data = Data(hexadecimalString: "4e00c6cc0d00ca0b000105006100067f5b000f")!
        let message = G7GlucoseMessage(data: data)!
        XCTAssertNil(message.trend)
    }

    func testTwoByteAge() {
        let data = Data(hexadecimalString: "4e00f9590200030200012a018f000610d9000f")!
        let message = G7GlucoseMessage(data: data)!
        XCTAssertEqual(298, message.age)
        XCTAssertEqual(154105, message.messageTimestamp)
        XCTAssertEqual(153807, message.glucoseTimestamp)
    }

    func testTwoByteAgeOnExpiredSensor() {
        let data = Data(hexadecimalString: "4e004d440e00d40b0001d46b650018036a000e")!
        let message = G7GlucoseMessage(data: data)!
        XCTAssertEqual(27604, message.age) // 7 hours after expiration
        XCTAssertEqual(934989, message.messageTimestamp)
        XCTAssertEqual(907385, message.glucoseTimestamp)
    }

    func testBackfill() {
        let data = Data(hexadecimalString: "cf5802008f00060f10")!
        let message = G7BackfillMessage(data: data)!
        XCTAssertEqual(153807, message.timestamp)
    }

}



// Activated 2022-09-24 17:39:31 +0000

//                                0  1  2 3 4 5  6  7  8  9 1011 1213 14 15 16 17 18
//                                     TTTTTTTT             AGAG BGBG SS          C
// 2022-09-24 17:47:23           4e 00 ea010000 04 00 00 01 0500 6c00 02 7e ff ff 02
// 2022-09-24 17:52:27           4e 00 1a030000 05 00 00 01 0900 5300 02 7e ff ff 02
// 2022-09-24 17:57:25           4e 00 44040000 06 00 00 01 0700 4500 02 e7 ff ff 02
// 2022-09-24 18:02:27           4e 00 73050000 07 00 00 01 0a00 3a00 02 f4 ff ff 02
// 2022-09-24 18:07:21           4e 00 99060000 08 00 00 01 0400 4800 06 02 ff ff 0e
// 2022-09-24 18:22:26           4e 00 220a0000 0b 00 00 01 0900 4f00 06 fe ff ff 0e

// 2022-09-24 18:27:22           4e 00 4a0b0000 0c 00 00 01 0500 4900 06 f9 37 00 0f
// 2022-09-24 18:27:23  (txInfo: 7815(379013053518), SW13354, 73 mg⁠/⁠dL, Predictive: 55 mg⁠/⁠dL, Rate: -0.7 @ 2022-09-24T13:27:17-05:00, sessionInfo: Optional(Start: 2022-09-24T12:40:17-05:00, End: 2022-10-05T00:40:17-05:00)), isTimeCertain: true

// 2022-09-24 22:32:24           4e 00 b7440000 3d 00 00 01 0600 7f00 06 03 83 00 0f
//2022-09-24 17:32:27.248461 -0500    info    388    <Missing Description>    Dexcom G7    DisplayState: displayingGlucose(txInfo: 7815(379013053518), SW13354, 127 mg⁠/⁠dL, Predictive: 131 mg⁠/⁠dL, Rate: 0.3 @ 2022-09-24T17:32:18-05:00, sessionInfo: Optional(Start: 2022-09-24T12:40:18-05:00, End: 2022-10-05T00:40:18-05:00)), isTimeCertain: true




//                                            0  1  2 3 4 5  6  7  8  9 1011 1213 14 15 16 17 18
//                                                 TTTTTTTT             AGAG BGBG SS          C
// 2022-10-04 23:27:39  106 timestamp:902888 4e 00 e8c60d00 c5 0b 00 01 0300 6a00 06 01 6a 00 0f
// 2022-10-04 23:32:40  101 timestamp:903189 4e 00 15c80d00 c6 0b 00 01 0400 6500 06 fe 61 00 0f
// 2022-10-04 23:37:39  98  timestamp:903488 4e 00 40c90d00 c7 0b 00 01 0300 6200 06 fc 5e 00 0f
// 2022-10-04 23:42:39  100 timestamp:903789 4e 00 6dca0d00 c8 0b 00 01 0400 6400 06 ff 5e 00 0f
// 2022-10-04 23:47:41  97  timestamp:904090 4e 00 9acb0d00 c9 0b 00 01 0500 6100 06 fd 5c 00 0f

// 2022-10-04 23:52:41  97  timestamp:904390 4e 00 c6cc0d00 ca 0b 00 01 0500 6100 06 fe 5b 00 0f

// 2022-10-04 23:52:41.100991 -0500    info    289    <Missing Description>    Dexcom G7    calBounds(signature=65,lastBG=100,lastBGTime=901259,processing=completeHigh,permitted=true,lastDisplay=phone,lastProcessingTime=901565)
// 2022-10-04 23:52:41.260740 -0500    info    289    <Missing Description>    Dexcom G7    DisplayState: displayingGlucose(txInfo: 7815(379013053518), SW13354, 97 mg⁠/⁠dL, Predictive: 91 mg⁠/⁠dL, Rate: -0.2 @ 2022-10-04T23:52:36-05:00, sessionInfo: Optional(Start: 2022-09-24T12:40:36-05:00, End: 2022-10-05T00:40:36-05:00)), isTimeCertain: true
//

// 2022-10-04 23:57:52  98  timestamp:904701 4e 00 fdcd0d00 cb 0b 00 01 1000 6200 06 00 5c 00 0f
// 2022-10-05 00:02:40  96  timestamp:904989 4e 00 1dcf0d00 cc 0b 00 01 0400 6000 06 fe 5b 00 0f
// 2022-10-05 00:07:39  95  timestamp:905288 4e 00 48d00d00 cd 0b 00 01 0300 5f00 06 fe 5a 00 0f
// 2022-10-05 08:17:43  101 timestamp:934692 4e 00 24430e00 d4 0b 00 01 ab6a 6500 18 03 6a 00 0e
// 2022-10-05 08:22:40  101 timestamp:934989 4e 00 4d440e00 d4 0b 00 01 d46b 6500 18 03 6a 00 0e
// 2022-10-05 08:27:40  101 timestamp:935289 4e 00 79450e00 d4 0b 00 01 006d 6500 18 03 6a 00 0e
// 2022-10-05 08:32:42  101 timestamp:935590 4e 00 a6460e00 d4 0b 00 01 2d6e 6500 18 03 6a 00 0e
// 2022-10-05 08:37:42  101 timestamp:935890 4e 00 d2470e00 d4 0b 00 01 596f 6500 18 03 6a 00 0e
// 2022-10-05 08:42:39  101 timestamp:936188 4e 00 fc480e00 d4 0b 00 01 8370 6500 18 03 6a 00 0e
// 2022-10-05 08:47:39  101 timestamp:936488 4e 00 284a0e00 d4 0b 00 01 af71 6500 18 03 6a 00 0e
