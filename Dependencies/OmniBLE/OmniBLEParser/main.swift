//
//  main.swift
//  OmniBLEParser
//
//  Based on OmniKitPacketParser/main.swift
//  Created by Joseph Moran on 02/02/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

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

// * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD send 17cae1dd00030e010003b1
// * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD receive 17cae1dd040a1d18002ab00000019fff0198
class LoopIssueReportParser {

    func parseLine(_ line: String) {
        let components = line.components(separatedBy: .whitespaces)
        let count = components.count
        if count == 8, let data = Data(hexadecimalString: components[count - 1]) {
            let direction = components[count - 2].padding(toLength: 7, withPad: " ", startingAt: 0)
            guard direction.lowercased() == "send   " || direction.lowercased() == "receive" else {
                return
            }
            let type: String
            if direction == "send   " {
                type = "SEND:   "
            } else if direction == "receive" {
                type = "RECEIVE:"
            } else {
                return
            }
            let time = components[1..<3].joined(separator: " ") // skip the +0000 portion
            do {
                let message = try Message(encodedData: data, checkCRC: false)
                print("\(type) \(time)  \(message)")
            } catch let error {
                print("Could not parse \(line): \(error)")
            }
        }
    }
}

// 2023-02-02 15:23:13.094289-0800 Loop[60606:22880823] [PodMessageTransport] Send(Hex): 1776c2c63c030e010000a0
// 2023-02-02 15:23:13.497849-0800 Loop[60606:22880823] [PodMessageTransport] Recv(Hex): 1776c2c6000a1d180064d800000443ff0000
class XcodeDashLogParser {

    func parseLine(_ line: String) {
        let components = line.components(separatedBy: .whitespaces)
        let count = components.count
        if count == 6, let data = Data(hexadecimalString: components[count - 1]) {
            let direction = components[count - 2].padding(toLength: 11, withPad: " ", startingAt: 0)
            let type: String
            if direction == "Send(Hex): " {
                type = "COMMAND:  "
            } else if direction == "Recv(Hex): " {
                type = "RESPONSE: "
            } else {
                return
            }
            let time = components[1].padding(toLength: 15, withPad: " ", startingAt: 0)
            do {
                let message = try Message(encodedData: data, checkCRC: false)
                print("\(type) \(time)  \(message)")
            } catch let error {
                print("Could not parse \(line): \(error)")
            }
        }
    }
}

// INFO[7699] pkg command; 0x0e; GET_STATUS; HEX, 1776c2c63c030e010000a0
// INFO[7699] pkg response 0x1d; HEX, 1776c2c6000a1d280064e80000057bff0000
class SimulatorLogParser {

    func parseLine(_ line: String) {
        let components = line.components(separatedBy: .whitespaces)
        let count = components.count - 1 // remove extra nl turd
        if count == 6 || count == 7, let data = Data(hexadecimalString: components[count - 1]) {
            let type: String
            if components[2] == "command;" {
                type = "COMMAND:  "
            } else if components[2] == "response" {
                type = "RESPONSE: "
            } else {
                return
            }
            let c0 = components[0]
            let startIndex = c0.index(c0.startIndex, offsetBy: 5)
            let endIndex = c0.index(c0.startIndex, offsetBy: 8)
            let time = String(c0[startIndex...endIndex])
            do {
                let message = try Message(encodedData: data, checkCRC: false)
                print("\(type) \(time)  \(message)")
            } catch let error {
                print("Could not parse \(line): \(error)")
            }
        }
    }
}

if CommandLine.argc <= 1 {
    print("No file name specified in command arguments to parse!")
    print("Set the Xcode Arguments Passed on Launch using Product->Scheme->Edit Scheme...")
    print("to specify the full path to sim, Loop Report, or Xcode log file(s) to parse.\n")
    exit(1)
}

for filename in CommandLine.arguments[1...] {
    let simulatorLogParser = SimulatorLogParser()
    let loopIssueReportParser = LoopIssueReportParser()
    let xcodeDashLogParser = XcodeDashLogParser()
    print("\nParsing \(filename)")

    do {
        let data = try String(contentsOfFile: filename, encoding: .utf8)
        let lines = data.components(separatedBy: .newlines)

        for line in lines {
            switch line {
            case Regex("; HEX, [0-9a-fA-F]+"):
                // INFO[7699] pkg command; 0x0e; GET_STATUS; HEX, 1776c2c63c030e010000a0
                // INFO[7699] pkg response 0x1d; HEX, 1776c2c6000a1d280064e80000057bff0000
                simulatorLogParser.parseLine(line)
            case Regex("(send|receive) [0-9a-fA-F]+"):
                // * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD send 17cae1dd00030e010003b1
                // * 2022-04-05 06:56:14 +0000 Omnipod-Dash 17CAE1DD receive 17cae1dd040a1d18002ab00000019fff0198
                loopIssueReportParser.parseLine(line)
            case Regex("(Send|Recv)\\(Hex\\): [0-9a-fA-F]+"):
                // 2023-02-02 15:23:13.094289-0800 Loop[60606:22880823] [PodMessageTransport] Send(Hex): 1776c2c63c030e010000a0
                // 2023-02-02 15:23:13.497849-0800 Loop[60606:22880823] [PodMessageTransport] Recv(Hex): 1776c2c6000a1d180064d800000443ff0000
                xcodeDashLogParser.parseLine(line)
            default:
                break
            }
        }
    } catch let error {
        print("Error: \(error)")
    }
}
