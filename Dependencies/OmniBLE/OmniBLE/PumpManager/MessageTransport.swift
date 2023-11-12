//
//  MessageTransport.swift
//  OmniBLE
//
//  Based on OmniKit/MessageTransport/MessageTransport.swift
//  Created by Pete Schwamb on 8/5/18.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

protocol MessageLogger: AnyObject {
    // Comms logging
    func didSend(_ message: Data)
    func didReceive(_ message: Data)
    func didError(_ message: String)
}

public struct MessageTransportState: Equatable, RawRepresentable {
    public typealias RawValue = [String: Any]

    public var ck: Data?
    public var noncePrefix: Data?
    public var eapSeq: Int // per session sequence #
    public var msgSeq: Int // 8-bit Dash MessagePacket sequence # (with ck)
    public var nonceSeq: Int // nonce sequence # (with noncePrefix)
    public var messageNumber: Int // 4-bit Omnipod Message # (for Omnipod command/responses Messages)
    
    init(ck: Data?, noncePrefix: Data?, eapSeq: Int = 1, msgSeq: Int = 0, nonceSeq: Int = 0, messageNumber: Int = 0) {
        self.ck = ck
        self.noncePrefix = noncePrefix
        self.eapSeq = eapSeq
        self.msgSeq = msgSeq
        self.nonceSeq = nonceSeq
        self.messageNumber = messageNumber
    }
    
    // RawRepresentable
    public init?(rawValue: RawValue) {
        guard
            let ckString = rawValue["ck"] as? String,
            let noncePrefixString = rawValue["noncePrefix"] as? String,
            let msgSeq = rawValue["msgSeq"] as? Int,
            let nonceSeq = rawValue["nonceSeq"] as? Int,
            let messageNumber = rawValue["messageNumber"] as? Int
            else {
                return nil
        }
        self.ck = Data(hex: ckString)
        self.noncePrefix = Data(hex: noncePrefixString)
        self.eapSeq = rawValue["eapSeq"] as? Int ?? 1
        self.msgSeq = msgSeq
        self.nonceSeq = nonceSeq
        self.messageNumber = messageNumber
    }
    
    public var rawValue: RawValue {
        return [
            "ck": ck?.hexadecimalString ?? "",
            "noncePrefix": noncePrefix?.hexadecimalString ?? "",
            "eapSeq": eapSeq,
            "msgSeq": msgSeq,
            "nonceSeq": nonceSeq,
            "messageNumber": messageNumber
        ]
    }

}

extension MessageTransportState: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## MessageTransportState",
            "eapSeq: \(eapSeq)",
            "msgSeq: \(msgSeq)",
            "nonceSeq: \(nonceSeq)",
            "messageNumber: \(messageNumber)",
        ].joined(separator: "\n")
    }
}

protocol MessageTransportDelegate: AnyObject {
    func messageTransport(_ messageTransport: MessageTransport, didUpdate state: MessageTransportState)
}

protocol MessageTransport {
    var delegate: MessageTransportDelegate? { get set }

    var messageNumber: Int { get }

    func sendMessage(_ message: Message) throws -> Message

    /// Asserts that the caller is currently on the session's queue
    func assertOnSessionQueue()
}

class PodMessageTransport: MessageTransport {
    private let COMMAND_PREFIX = "S0.0="
    private let COMMAND_SUFFIX = ",G0.0"
    private let RESPONSE_PREFIX = "0.0="
    
    private let manager: PeripheralManager
    
    private var nonce: Nonce?
    private var enDecrypt: EnDecrypt?

    private let log = OSLog(category: "PodMessageTransport")
    
    private(set) var state: MessageTransportState {
        didSet {
            self.delegate?.messageTransport(self, didUpdate: state)
        }
    }
    
    private(set) var ck: Data? {
        get {
            return state.ck
        }
        set {
            state.ck = newValue
        }
    }
    
    private(set) var noncePrefix: Data? {
        get {
            return state.noncePrefix
        }
        set {
            state.noncePrefix = newValue
        }
    }
    
    private(set) var eapSeq: Int {
        get {
            return state.eapSeq
        }
        set {
            state.eapSeq = newValue
        }
    }

    private(set) var msgSeq: Int {
        get {
            return state.msgSeq
        }
        set {
            state.msgSeq = newValue
        }
    }
    
    private(set) var nonceSeq: Int {
        get {
            return state.nonceSeq
        }
        set {
            state.nonceSeq = newValue
        }
    }
    
    private(set) var messageNumber: Int {
        get {
            return state.messageNumber
        }
        set {
            state.messageNumber = newValue
        }
    }

    private let myId: UInt32
    private let podId: UInt32
    
    weak var messageLogger: MessageLogger?
    weak var delegate: MessageTransportDelegate?

    init(manager: PeripheralManager, myId: UInt32, podId: UInt32, state: MessageTransportState) {
        self.manager = manager
        self.myId = myId
        self.podId = podId
        self.state = state
        
        guard let noncePrefix = self.noncePrefix, let ck = self.ck else { return }
        self.nonce = Nonce(prefix: noncePrefix)
        self.enDecrypt = EnDecrypt(nonce: self.nonce!, ck: ck)
    }
    
    private func incrementMsgSeq(_ count: Int = 1) {
        msgSeq = ((msgSeq) + count) & 0xff // msgSeq is the 8-bit Dash MessagePacket sequence #
    }

    private func incrementNonceSeq(_ count: Int = 1) {
        nonceSeq = nonceSeq + count
    }

    private func incrementMessageNumber(_ count: Int = 1) {
        messageNumber = ((messageNumber) + count) & 0b1111 // messageNumber is the 4-bit Omnipod Message #
    }

    /// Sends the given pod message over the encrypted Dash transport and returns the pod's response
    func sendMessage(_ message: Message) throws -> Message {
        
        guard manager.peripheral.state == .connected else {
            throw PodCommsError.podNotConnected
        }

        messageNumber = message.sequenceNum // reset our Omnipod message # to given value

        incrementMessageNumber() // bump to match expected Omnipod message # in response

        let dataToSend = message.encoded()
        log.default("Send(Hex): %{public}@", dataToSend.hexadecimalString)
        messageLogger?.didSend(dataToSend)

        let sendMessage = try getCmdMessage(cmd: message)

        let writeResult = manager.sendMessagePacket(sendMessage)
        switch writeResult {
        case .sentWithAcknowledgment:
            break;
        case .sentWithError(let error):
            messageLogger?.didError("Unacknowledged message. seq:\(message.sequenceNum), error = \(error)")
            throw PodCommsError.unacknowledgedMessage(sequenceNumber: message.sequenceNum, error: error)
        case .unsentWithError(let error):
            throw PodCommsError.commsError(error: error)
        }

        do {
            let response = try readAndAckResponse()
            incrementMessageNumber() // bump the 4-bit Omnipod Message number
            return response
        } catch {
            messageLogger?.didError("Unacknowledged message. seq:\(message.sequenceNum), error = \(error)")
            throw PodCommsError.unacknowledgedMessage(sequenceNumber: message.sequenceNum, error: error)
        }
    }
    
    private func getCmdMessage(cmd: Message) throws -> MessagePacket {
        guard let enDecrypt = self.enDecrypt else {
            throw PodCommsError.podNotConnected
        }

        incrementMsgSeq()

        let wrapped = StringLengthPrefixEncoding.formatKeys(
            keys: [COMMAND_PREFIX, COMMAND_SUFFIX],
            payloads: [cmd.encoded(), Data()]
        )

        let msg = MessagePacket(
            type: MessageType.ENCRYPTED,
            source: self.myId,
            destination: self.podId,
            payload: wrapped,
            sequenceNumber: UInt8(msgSeq),
            eqos: 1
        )

        incrementNonceSeq()
        return try enDecrypt.encrypt(msg, nonceSeq)
    }
    
    func readAndAckResponse() throws -> Message {
        guard let enDecrypt = self.enDecrypt else { throw PodCommsError.podNotConnected }

        let readResponse = try manager.readMessagePacket()
        guard let readMessage = readResponse else {
            throw PodProtocolError.messageIOException("Could not read response")
        }

        incrementNonceSeq()
        let decrypted = try enDecrypt.decrypt(readMessage, nonceSeq)

        let response = try parseResponse(decrypted: decrypted)

        incrementMsgSeq()
        incrementNonceSeq()
        let ack = try getAck(response: decrypted)
        let ackResult = manager.sendMessagePacket(ack)
        guard case .sentWithAcknowledgment = ackResult else {
            throw PodProtocolError.messageIOException("Could not write $msgType: \(ackResult)")
        }

        // verify that the Omnipod message # matches the expected value
        guard response.sequenceNum == messageNumber else {
            throw MessageError.invalidSequence
        }

        return response
    }
    
    private func parseResponse(decrypted: MessagePacket) throws -> Message {

        let data = try StringLengthPrefixEncoding.parseKeys([RESPONSE_PREFIX], decrypted.payload)[0]
        log.debug("Received decrypted response: %{public}@ in packet: %{public}@", data.hexadecimalString, decrypted.payload.hexadecimalString)

        // Dash pods generates a CRC16 for Omnipod Messages, but the actual algorithm is not understood and doesn't match the CRC16
        // that the pod enforces for incoming Omnipod command message. The Dash PDM explicitly ignores the CRC16 for incoming messages,
        // so we ignore them as well and rely on higher level BLE & Dash message data checking to provide data corruption protection.
        let response = try Message(encodedData: data, checkCRC: false)

        log.default("Recv(Hex): %{public}@", data.hexadecimalString)
        messageLogger?.didReceive(data)

        return response
    }
    
    private func getAck(response: MessagePacket) throws -> MessagePacket {
        guard let enDecrypt = self.enDecrypt else { throw PodCommsError.podNotConnected }

        let ackNumber = (UInt(response.sequenceNumber) + 1) & 0xff
        let msg = MessagePacket(
            type: MessageType.ENCRYPTED,
            source: response.destination.toUInt32(),
            destination: response.source.toUInt32(),
            payload: Data(),
            sequenceNumber: UInt8(msgSeq),
            ack: true,
            ackNumber: UInt8(ackNumber),
            eqos: 0
        )
        return try enDecrypt.encrypt(msg, nonceSeq)
    }
    
    func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(manager.queue))
    }
}

extension PodMessageTransport: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## PodMessageTransport",
            "eapSeq: \(eapSeq)",
            "msgSeq: \(msgSeq)",
            "nonceSeq: \(nonceSeq)",
            "messageNumber: \(messageNumber)",
        ].joined(separator: "\n")
    }
}
