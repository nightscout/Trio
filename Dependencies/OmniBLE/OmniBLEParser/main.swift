//
//  main.swift
//  OmniBLEParser
//
//  Based on OmniKitPacketParser/main.swift
//  Created by Joseph Moran on 02/02/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

// These options can be forced off by using the -q option argument
fileprivate var printDate: Bool = true // whether to print the date (when available) along with the time (when available)
fileprivate var printFullMessage: Bool = true // whether to print full message decode including the address and seq

//from NSHipster - http://nshipster.com/swift-literal-convertible/
struct Regex {
    let pattern: String
    let options: NSRegularExpression.Options!

    private var matcher: NSRegularExpression {
        return try! NSRegularExpression(pattern: self.pattern, options: self.options)
    }

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        self.pattern = pattern
        self.options = options
    }

    func match(string: String, options: NSRegularExpression.MatchingOptions = []) -> Bool {
        return self.matcher.numberOfMatches(in: string, options: options, range: NSMakeRange(0, string.count)) != 0
    }
}

protocol RegularExpressionMatchable {
    func match(regex: Regex) -> Bool
}

extension String: RegularExpressionMatchable {
    func match(regex: Regex) -> Bool {
        return regex.match(string: self)
    }
}

func ~=<T: RegularExpressionMatchable>(pattern: Regex, matchable: T) -> Bool {
    return matchable.match(regex: pattern)
}

func printDecoded(timeStr: String, hexString: String)
{
    guard let data = Data(hexadecimalString: hexString), data.count >= 10 else {
        print("Bad hex string: \(hexString)")
        return
    }
    do {
        // The block type is right after the 4-byte address and the B9 and BLEN bytes
        guard let blockType = MessageBlockType(rawValue: data[6]) else {
            throw MessageBlockError.unknownBlockType(rawVal: data[6])
        }
        let type: String
        let checkCRC: Bool
        switch blockType {
        case .statusResponse, .podInfoResponse, .versionResponse, .errorResponse:
            type = "RESPONSE: "
            // Don't currently understand how to check the CRC16 the DASH pods generate
            checkCRC = false
        default:
            type = "COMMAND:  "
            checkCRC = true
        }
        let message = try Message(encodedData: data, checkCRC: checkCRC)
        if printFullMessage {
            // print the complete message with the address and seq
            print("\(type)\(timeStr) \(message)")
        } else {
            // skip printing the address and seq for each message
            print("\(type)\(timeStr) \(message.messageBlocks)")
        }
    } catch let error {
        print("Could not parse \(hexString): \(error)")
    }
}

// * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD send 17cae1dd00030e010003b1
// * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD receive 17cae1dd040a1d18002ab00000019fff0198
func parseLoopReportLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    let hexString = components[components.count - 1]

    let date = components[1]
    let time = components[2]
    let timeStr = printDate ? date + " " + time : time

    printDecoded(timeStr: timeStr, hexString: hexString)
}

// 2023-02-02 15:23:13.094289-0800 Loop[60606:22880823] [PodMessageTransport] Send(Hex): 1776c2c63c030e010000a0
// 2023-02-02 15:23:13.497849-0800 Loop[60606:22880823] [PodMessageTransport] Recv(Hex): 1776c2c6000a1d180064d800000443ff0000
func parseLoopXcodeLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    let hexString = components[components.count - 1]

    let date = components[0]
    let time = components[1].padding(toLength: 15, withPad: " ", startingAt: 0)  // skip the -0800 portion
    let timeStr = printDate ? date + " " + time : time

    printDecoded(timeStr: timeStr, hexString: hexString)
}

// N.B. Simulator output typically has a space after the hex string!
// INFO[7699] pkg command; 0x0e; GET_STATUS; HEX, 1776c2c63c030e010000a0
// INFO[7699] pkg response 0x1d; HEX, 1776c2c6000a1d280064e80000057bff0000
// INFO[2023-09-04T18:17:06-07:00] pkg command; 0x07; GET_VERSION; HEX, ffffffff00060704ffffffff82b2
// INFO[2023-09-04T18:17:06-07:00] pkg response 0x1; HEX, ffffffff04170115040a00010300040208146db10006e45100ffffffff0000
func parseSimulatorLogLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    var hexStringIndex = components.count - 1
    let hexString: String
    if components[hexStringIndex].isEmpty {
        hexStringIndex -= 1 // back up to handle a trailing space
    }
    hexString = components[hexStringIndex]

    let c0 = components[0]
    // start at 5 for printDate or shorter "INFO[7699]" format
    let offset = printDate || c0.count <= 16 ? 5 : 16
    let startIndex = c0.index(c0.startIndex, offsetBy: offset)
    let endIndex = c0.index(c0.startIndex, offsetBy: c0.count - 2)
    let timeStr = String(c0[startIndex...endIndex])

    printDecoded(timeStr: timeStr, hexString: hexString)
}


// iAPS or Trio log file
// iAPS_log 2024-05-08T00:03:57-0700 [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 576 - DEV: Device message: 17ab48aa20071f05494e532e0201d5
// iAPS or Trio Xcode log with timestamp
// 2024-05-25 14:16:54.933281-0700 FreeAPS[2973:2299225] [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 566 DEV: Device message: 170f1e3710080806494e532e000081ab
// iAPS or Trio Xcode log with no timestamp
// DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 566 DEV: Device message: 170f1e3710080806494e532e000081ab
func parseFreeAPSLogOrXcodeLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    let hexString = components[components.count - 1]

    if components.count > 9 {
        // have a timestamp
        let date = components[0].prefix(10)
        let time: String
        if components.count == 12 {
            // iAPS or Trio log file with date and time joined with a "T", e.g., 2024-05-25T00:26:05-0700
            let dateAndTimeComponents = components[0].components(separatedBy: "T")
            time = dateAndTimeComponents[1].padding(toLength: 8, withPad: " ", startingAt: 0) // skip the -0700 portion
        } else {
            // Xcode log file with separate date and time, e.g., 2024-05-25 14:16:53.571361-0700
            time = components[1].padding(toLength: 15, withPad: " ", startingAt: 11) // skip the -0700 portion
        }
        let timeStr = printDate ? date + " " + time : time
        printDecoded(timeStr: timeStr, hexString: hexString)
    } else {
        // no timestamp
        printDecoded(timeStr: "", hexString: hexString)
    }
}

// 2020-11-04 13:38:34.256  1336  6945 I PodComm pod command: 08202EAB08030E01070319
// 2020-11-04 13:38:34.979  1336  1378 V PodComm response (hex) 08202EAB0C0A1D9800EB80A400042FFF8320
func parseDashPDMLogLine(_ line: String) {
    let components = line.components(separatedBy: .whitespaces)
    let hexString = components[components.count - 1]

    let date = components[0]
    let time = components[1]
    let timeStr = printDate ? date + " " + time : time

    printDecoded(timeStr: timeStr, hexString: hexString)
}

func usage() {
    print("Usage: [-q] file...")
    print("Set the Xcode Arguments Passed on Launch using Product->Scheme->Edit Scheme...")
    print("to specify the full path to Loop Report, Xcode log, pod simulator log, iAPS log, Trio log or DASH PDM log file(s) to parse.\n")
    exit(1)
}

if CommandLine.argc <= 1 {
    usage()
}

for arg in CommandLine.arguments[1...] {
    if arg == "-q" {
        printDate = false
        printFullMessage = false
        continue
    } else if arg.starts(with: "-") {
        // no other arguments curently supported
        usage()
    }

    print("\nParsing \(arg)")
    do {
        let data = try String(contentsOfFile: arg, encoding: .utf8)
        let lines = data.components(separatedBy: .newlines)

        for line in lines {
            switch line {
            // Loop Report file
            // * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD send 17cae1dd00030e010003b1
            // * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD receive 17cae1dd040a1d18002ab00000019fff0198
            case Regex("(send|receive) [0-9a-fA-F]+$"):
                parseLoopReportLine(line)

            // Loop Xcode log
            // 2023-02-02 15:23:13.094289-0800 Loop[60606:22880823] [PodMessageTransport] Send(Hex): 1776c2c63c030e010000a0
            // 2023-02-02 15:23:13.497849-0800 Loop[60606:22880823] [PodMessageTransport] Recv(Hex): 1776c2c6000a1d180064d800000443ff0000
            case Regex(" Loop\\[.*\\] \\[PodMessageTransport\\] (Send|Recv)\\(Hex\\): [0-9a-fA-F]+$"):
                parseLoopXcodeLine(line)

            // Simulator log file (N.B. typically has a trailing space!)
            // INFO[7699] pkg command; 0x0e; GET_STATUS; HEX, 1776c2c63c030e010000a0
            // INFO[7699] pkg response 0x1d; HEX, 1776c2c6000a1d280064e80000057bff0000
            case Regex("; HEX, [0-9a-fA-F]+ $"), Regex("; HEX, [0-9a-fA-F]+$"):
                parseSimulatorLogLine(line)

            // iAPS or Trio log file
            // iAPS_log 2024-05-08T00:03:57-0700 [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 576 - DEV: Device message: 17ab48aa20071f05494e532e0201d5
            // iAPS or Trio Xcode log with timestamp
            // 2024-05-25 14:16:54.933281-0700 FreeAPS[2973:2299225] [DeviceManager] DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 566 DEV: Device message: 170f1e3710080806494e532e000081ab
            // iAPS or Trio Xcode log with no timestamp
            // DeviceDataManager.swift - deviceManager(_:logEventForDeviceIdentifier:type:message:completion:) - 566 DEV: Device message: 170f1e3710080806494e532e000081ab
            case Regex("Device message: [0-9a-fA-F]+$"):
                parseFreeAPSLogOrXcodeLine(line)

            // DASH PDM log file
            // 2020-11-04 21:35:52.218  1336  1378 I PodComm pod command: 08202EAB30030E010000BC
            // 2020-11-04 21:35:52.575  1336  6945 V PodComm response (hex) 08202EAB340A1D18018D2000000BA3FF81D9
            case Regex("I PodComm pod command: "), Regex("V PodComm response \\(hex\\) "):
                parseDashPDMLogLine(line)

            default:
                break
            }
        }
    } catch let error {
        print("Error: \(error)")
    }
    print("\n")
}
