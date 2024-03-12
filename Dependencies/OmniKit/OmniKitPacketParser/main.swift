//
//  main.swift
//  OmniKitPacketParser
//
//  Created by Pete Schwamb on 12/19/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

let printRepeats = true

enum ParsingError: Error {
    case invalidPacketType(str: String)
}

extension PacketType {
    init(rtlomniString: String) throws {
        switch rtlomniString {
        case "PTYPE:POD":
            self = .pod
        case "PTYPE:PDM":
            self = .pdm
        case "PTYPE:CON":
            self = .con
        case "PTYPE:ACK":
            self = .ack
        default:
            throw ParsingError.invalidPacketType(str: rtlomniString)
        }
    }
}

extension String {
    func valPart() -> String {
        return String(split(separator: ":")[1])
    }
}

extension Int {
    func nextPacketNumber(_ increment: Int) -> Int {
        return (self + increment) & 0b11111
    }
}

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


class LoopIssueReportParser {
    // * 2018-12-27 01:46:56 +0000 send 1f0e41a6101f1a0e81ed50b102010a0101a000340034170d000208000186a00000000000000111
    func parseLine(_ line: String) {
        let components = line.components(separatedBy: .whitespaces)
        if components.count == 8, let data = Data(hexadecimalString: components[7]) {
            let direction = components[6].padding(toLength: 7, withPad: " ", startingAt: 0)
            guard direction.lowercased() == "send   " || direction.lowercased() == "receive" else {
                return
            }
            let date = components[1..<4].joined(separator: " ")
            do {
                let message = try Message(encodedData: data, checkCRC: false)
                print("\(date) \(direction) \(message)")
            } catch let error as MessageError {
                if let packet = try? Packet(encodedData: data) {
                    print("\(date) \(direction) packet \(packet)")
                } else {
                    switch error {
                    case .notEnoughData:
                        if data.count == 4 {
                            // This is from a packet, not a message, and we don't have the full packet info here
                            print("\(date) \(direction) ack \(components[7])")
                        } else {
                            print("Could not parse \(line)")
                        }
                    default:
                        print("Could not parse \(line): \(error.localizedDescription)")
                    }
                }
            } catch let error {
                print("Could not parse \(line): \(error)")
            }
        }
    }
}

class RTLOmniLineParser {
    private var lastPacket: ArraySlice<String>? = nil
    private var messageDate: String = ""
    private var lastMessageData = Data()
    private var messageData = Data()
    private var messageSource: PacketType = .pdm
    private var address: String = ""
    private var packetNumber: Int = 0
    private var repeatCount: Int = 0
    
    func parseLine(_ line: String) {
        let components = line.components(separatedBy: .whitespaces)
        if components.count > 3, let packetType = try? PacketType(rtlomniString: components[2]) {
            if lastPacket == components[1...] {
                return
            }
            lastPacket = components[1...]
            switch packetType {
            case .pod, .pdm:
                if components.count != 9 {
                    print("Invalid line:\(line)")
                    return
                }
                // 2018-12-19T20:50:48.3d ID1:1f0b3557 PTYPE:POD SEQ:31 ID2:1f0b3557 B9:00 BLEN:205 BODY:02cb510032602138800120478004213c80092045800c203980 CRC:a8
                // 2018-05-25T13:03:51.765792 ID1:ffffffff PTYPE:POD SEQ:01 ID2:ffffffff B9:04 BLEN:23 BODY:011502070002070002020000aa6400088cb98f1f16b11e82a5 CRC:72
                messageDate = components[0]
                messageSource = packetType
                address = String(components[1].valPart())
                packetNumber = Int(components[3].valPart())!
                let messageAddress = String(components[4].valPart())
                let b9 = String(components[5].valPart())
                if messageData.count > 0 {
                    print("Dropping incomplete message data: \(messageData.hexadecimalString)")
                }
                messageData = Data(hexadecimalString: messageAddress + b9)!
                let messageLen = UInt8(components[6].valPart())!
                messageData.append(messageLen)
                let packetData = Data(hexadecimalString: components[7].valPart())!
                messageData.append(packetData)
            case .con:
                // 2018-12-19T05:19:04.3d ID1:1f0b3557 PTYPE:CON SEQ:12 CON:0000000000000126 CRC:60
                let packetAddress = String(components[1].valPart())
                let nextPacketNumber = Int(components[3].valPart())!
                if (packetAddress == address) && (nextPacketNumber == packetNumber.nextPacketNumber(2)) {
                    packetNumber = nextPacketNumber
                    let packetData = Data(hexadecimalString: components[4].valPart())!
                    messageData.append(packetData)
                } else if packetAddress != address {
                    print("mismatched address: \(line)")
                } else if nextPacketNumber != packetNumber.nextPacketNumber(2) {
                    print("mismatched packet number: \(nextPacketNumber) != \(packetNumber.nextPacketNumber(2)) \(line)")
                }
            case .ack:
                print("Ack: \(line)")
            }
            do {
                let message = try Message(encodedData: messageData)
                let messageStr = "\(messageDate) \(messageSource) \(message)"
                if lastMessageData == messageData {
                    repeatCount += 1
                    if printRepeats {
                        print(messageStr + " repeat:\(repeatCount)")
                    }
                } else {
                    lastMessageData = messageData
                    repeatCount = 0
                    print(messageStr)
                }
                messageData = Data()
            } catch MessageError.notEnoughData {
                return
            } catch let error {
                print("Error decoding message: \(error)")
            }
        }
    }
}

class XcodeLogParser {
    private var lastPacket: ArraySlice<String>? = nil
    private var messageDate: String = ""
    private var sendMessageData = Data()
    private var recvMessageData = Data()
    private var messageSource: PacketType = .pdm
    private var address: String = ""
    private var packetNumber: Int = 0
    private var repeatCount: Int = 0

    func parseLine(_ line: String) {
        let components = line.components(separatedBy: .whitespaces)
        if let rlCmd = components.last {
            let direction = components[5].prefix(4)
            let timeStamp = "\(components[0]) \(components[1])"

            switch direction {
            case "Send":
                let cmdCode = rlCmd.prefix(4).suffix(2)
                switch(cmdCode) {
                case "05": // SendAndListen
                    let packetData = Data(hexadecimalString: String(rlCmd.suffix(rlCmd.count - 28)))!
                    do {
                        let packet = try Packet(encodedData: packetData)
                        print("\(timeStamp) \(direction) \(packet)")
                        if packet.packetType == .con {
                            sendMessageData.append(packet.data)
                        } else {
                            sendMessageData = packet.data
                        }
                        if let message = try? Message(encodedData: sendMessageData) {
                            print("\(timeStamp) \(direction) \(message)")
                            sendMessageData = Data()
                        }
                        if packet.packetType == .ack {
                            sendMessageData = Data()
                        }
                    } catch let error {
                        print("Error parsing \(rlCmd): \(error)")
                    }
                case "06":
                    print("Configure Register: \(cmdCode) \(rlCmd)")
                default:
                    print("Unhandled command: \(direction) \(cmdCode) \(rlCmd)")
                }
            case "Recv":
                let status = rlCmd.prefix(2)
                switch(status) {
                case "dd":
                    if rlCmd.count > 6 {
                        let packetData = Data(hexadecimalString: String(rlCmd.suffix(rlCmd.count - 6)))!
                        do {
                            let packet = try Packet(encodedData: packetData)
                            print("\(timeStamp) \(direction) \(packet)")
                            if packet.packetType == .con {
                                recvMessageData.append(packet.data)
                            } else {
                                recvMessageData = packet.data
                            }
                            do {
                                let message = try Message(encodedData: recvMessageData)
                                print("\(timeStamp) \(direction) \(message)")
                                recvMessageData = Data()
                            } catch MessageError.notEnoughData {
                                break
                            } catch let error {
                                print("Message not parsed from packet data \(recvMessageData.hexadecimalString): \(error)")
                            }
                        } catch let error {
                            print("Error parsing \(rlCmd): \(error)")
                        }
                    } else {
                        //print("\(timeStamp) \(direction) \(rlCmd)")
                    }
                case "aa":
                    print("\(timeStamp) Receive Timeout")
                default:
                    print("Unhandled response type: \(direction) \(rlCmd)")
                }
            default:
                break
            }
        }
    }
}

if CommandLine.argc <= 1 {
    print("No file names specified in command arguments to parse!")
    print("Set the Xcode Arguments Passed on Launch using Product->Scheme->Edit Scheme...")
    print("to specify the full path to rtl, Loop Report, or Xcode log file(s) to parse.\n")
    exit(1)
}

for filename in CommandLine.arguments[1...] {
    let rtlOmniParser = RTLOmniLineParser()
    let loopIssueReportParser = LoopIssueReportParser()
    let xcodeLogParser = XcodeLogParser()
    print("Parsing \(filename)")

    do {
        let data = try String(contentsOfFile: filename, encoding: .utf8)
        let lines = data.components(separatedBy: .newlines)

        for line in lines {
            switch line {
            case Regex("ID1:[0-9a-fA-F]+ PTYPE:"):
                // 2018-12-24T10:58:41.3d ID1:1f0f407e PTYPE:POD SEQ:02 ID2:1f0f407e B9:3c BLEN:24 BODY:0216020d0000000000d23102b103ff02b1000008ab08016e83 CRC:c2
                // 2018-05-25T13:03:51.765792 ID1:ffffffff PTYPE:POD SEQ:01 ID2:ffffffff B9:04 BLEN:23 BODY:011502070002070002020000aa6400088cb98f1f16b11e82a5 CRC:72
                rtlOmniParser.parseLine(line)
            case Regex("(send|receive) [0-9a-fA-F]+"):
                // 2018-12-27 01:46:56 +0000 send 1f0e41a6101f1a0e81ed50b102010a0101a000340034170d000208000186a00000000000000111
                loopIssueReportParser.parseLine(line)
            case Regex("RL (Send|Recv) ?\\(single\\): [0-9a-fA-F]+"):
                // 2019-02-09 08:23:27.605518-0800 Loop[2978:2294033] [PeripheralManager+RileyLink] RL Send (single): 17050005000000000002580000281f0c27a4591f0c27a447
                // 2019-02-09 08:23:28.262888-0800 Loop[2978:2294816] [PeripheralManager+RileyLink] RL Recv(single): dd0c2f1f079e674b1f079e6769
                xcodeLogParser.parseLine(line)
            default:
                break
            }
        }
    } catch let error {
        print("Error: \(error)")
    }
}
