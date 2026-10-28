import CGMBLEKit
import CryptoKit
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import SyaiKit
import TidepoolServiceKit

struct SensitiveValues {
    private(set) var values: [Redactor.ExactValue] = []

    private typealias Field = (path: [String], kind: Redactor.Kind)

    private static let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    // rawState paths per pluginIdentifier; kits persist these values verbatim
    private static let fields: [String: [Field]] = [
        "Omni": ["podState", "previousPodState"].flatMap { pod in
            [
                ([pod, "lotNo"], .pumpSerial),
                ([pod, "lotSeq"], .pumpSerial),
                ([pod, "lot"], .pumpSerial),
                ([pod, "tid"], .pumpSerial),
                ([pod, "bleIdentifier"], .device),
                ([pod, "ltk"], .secret),
                ([pod, "signingKey"], .secret)
            ]
        } + [(["rileyLinkConnectionManagerState", "autoConnectIDs"], .device)],
        "Minimed500": [
            (["pumpID"], .pumpSerial),
            (["rileyLinkConnectionManagerState", "autoConnectIDs"], .device)
        ],
        "Dana": [
            (["deviceName"], .pumpSerial),
            (["bleIdentifier"], .device),
            (["ble5Keys"], .secret),
            (["pairingKey"], .secret),
            (["randomPairingKey"], .secret)
        ],
        "Medtrum": [
            (["pumpSN"], .pumpSerial),
            (["sessionToken"], .secret),
            (["backupSessionToken"], .secret),
            (["peripheralIdentifier"], .device)
        ],
        "TandemPumpManager": [
            (["pumpState", "pumpSerial"], .pumpSerial),
            (["pumpState", "pcbSerialNumber"], .pumpSerial),
            (["pumpState", "peripheralUuid"], .device),
            (["pumpState", "pincode"], .secret),
            (["pumpState", "derivedSecret"], .secret),
            (["pumpState", "serverNonce"], .secret)
        ],
        "DexG5Transmitter": [(["transmitterID"], .cgmSerial)],
        "DexG6Transmitter": [(["transmitterID"], .cgmSerial)],
        "G7CGMManager": [
            (["sensorID"], .cgmSerial),
            (["previousSensor", "sensorID"], .cgmSerial),
            (["previousSensor", "serialNumber"], .cgmSerial),
            (["peripheralIdentifier"], .device),
            (["sharedKey"], .secret),
            (["shareUsername"], .account)
        ],
        "SyaiCGMManager": [
            (["sensors", "activeMAC"], .device),
            (["sensors", "pendingBind", "mac"], .device)
        ],
        "LibreLoopCGMManager": [
            (["sensorSerial"], .cgmSerial),
            (["bleAddress"], .device),
            (["peripheralID"], .device),
            (["blePIN"], .secret)
        ],
        "EversenseKit": [
            (["bleNameString"], .cgmSerial),
            (["transmitterId"], .cgmSerial),
            (["sensorId"], .cgmSerial),
            (["peripheralIdentifier"], .device),
            (["username"], .account),
            (["password"], .secret),
            (["accessToken"], .secret),
            (["clientIdV2"], .secret)
        ],
        "AccuChek": [
            (["deviceName"], .cgmSerial),
            (["previousDeviceName"], .cgmSerial),
            (["sensorInfo", "serialNumber"], .cgmSerial),
            (["pinCode"], .secret),
            (["aesKey"], .secret),
            (["accessToken"], .secret),
            (["refreshToken"], .secret)
        ]
    ]

    mutating func add(_ value: String?, _ kind: Redactor.Kind) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count >= Redactor.minimumLength
        else { return }
        values.append(Redactor.ExactValue(value: value, kind: kind))
        // Query strings and form bodies carry values percent-encoded, with spaces as %20 or +
        if let encoded = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved), encoded != value {
            values.append(Redactor.ExactValue(value: encoded, kind: kind))
            values.append(Redactor.ExactValue(value: encoded.replacingOccurrences(of: "%20", with: "+"), kind: kind))
        }
    }

    mutating func addNightscout(url: String?, secret: String?) {
        if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            // Without the trailing slash, so request paths keep theirs
            add(url.hasSuffix("/") ? String(url.dropLast()) : url, .nightscoutURL)
            add(URL(string: url)?.host, .nightscoutHost)
        }
        if let secret, !secret.isEmpty {
            add(secret, .apiSecret)
            // Nightscout requests carry the secret's SHA-1 in the api-secret header
            add(Insecure.SHA1.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined(), .apiSecret)
        }
    }

    mutating func addTrioIdentifiers(defaults: UserDefaults = .standard) {
        add(defaults.string(forKey: "trioRemoteControlSharedSecret"), .remoteSecret)
        add(defaults.string(forKey: "deviceToken"), .pushToken)
        add(PropertyPersistentFlags.shared.telemetryInstallId, .installID)
    }

    mutating func add(tidepool service: TidepoolService?) {
        guard let session = service?.session else { return }
        add(session.accessToken, .secret)
        add(session.refreshToken, .secret)
        add(session.username, .email)
        add(session.userId, .account)
    }

    mutating func add(_ manager: DeviceManager) {
        add(rawState: manager.rawState, pluginIdentifier: manager.pluginIdentifier)
        addProperties(of: manager)
    }

    mutating func add(rawState state: [String: Any], pluginIdentifier: String) {
        for field in Self.fields[pluginIdentifier] ?? [] {
            for value in Self.strings(at: field.path, in: state) {
                add(value, field.kind)
            }
        }
        switch pluginIdentifier {
        case "Omni":
            // Addresses print as 8 hex digits; packet dumps embed them glued, which whole-token matching leaves alone
            for pod in ["podState", "previousPodState"] {
                add(Self.hex32((state[pod] as? [String: Any])?["address"]), .device)
            }
            add(Self.hex32(state["controllerId"]), .device)
            add(Self.hex32(state["podId"]), .device)
        case "Medtrum":
            // Advertisements carry the serial byte-reversed
            add((state["pumpSN"] as? Data).map { Self.hex(Data($0.reversed())) }, .pumpSerial)
        case "G7CGMManager":
            if let code = (state["previousSensor"] as? [String: Any])?["pairingCode"] as? String {
                // Four digits collide with numbers, so match the code only as debugDescription prints it
                add("\"pairingCode\": \"\(code)\"", .secret)
            }
        case "TandemPumpManager":
            // The pump state's debug description prints the pairing secrets as base64
            let pump = state["pumpState"] as? [String: Any]
            add((pump?["derivedSecret"] as? Data)?.base64EncodedString(), .secret)
            add((pump?["serverNonce"] as? Data)?.base64EncodedString(), .secret)
        case "LibreLoopCGMManager":
            // The sensor advertises its MAC without colons; receiver IDs log as a little-endian UInt32
            add((state["bleAddress"] as? String)?.replacingOccurrences(of: ":", with: "").uppercased(), .device)
            add((state["receiverID"] as? Data).map { Self.hex(Data($0.reversed())) }, .device)
        default:
            break
        }
    }

    private mutating func addProperties(of manager: DeviceManager) {
        switch manager {
        case let manager as TransmitterManager:
            let credentials = manager.shareManager.shareService.credentialValues
            add(credentials.first ?? nil, .account)
            add(credentials.dropFirst().first ?? nil, .secret)
        case let manager as G7CGMManager:
            add(manager.state.transmitterVersion?.serialNumberString, .cgmSerial)
        case is SyaiCGMManager:
            // The account lives in the kit's own keychain item, not in rawState
            guard let account = SyaiKeychain.loadAccount() else { return }
            add(account.email, .email)
            add(account.userId, .account)
            for secret in [account.password, account.refreshToken, account.accessToken, account.glucoseSecretKey] {
                add(secret, .secret)
            }
        case let manager as LibreTransmitterManagerV3:
            add(UserDefaults.standard.currentSensor, .cgmSerial)
            add(UserDefaults.standard.preSelectedDevice, .device)
            add(manager.sensorInfoObservable.sensorSerial, .cgmSerial)
            add(manager.transmitterInfoObservable.transmitterMacAddress, .device)
        default:
            guard manager.pluginIdentifier == "EversenseKit",
                  let data = try? KeychainManager().getGenericPasswordForServiceAsData("com.bastiaanv.Eversensekit"),
                  let credentials = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return }
            add(credentials["username"], .account)
            add(credentials["password"], .secret)
        }
    }

    private static func strings(at path: [String], in state: [String: Any]) -> [String] {
        guard let key = path.first else { return [] }
        let value = state[key]
        if path.count > 1 {
            return (value as? [String: Any]).map { strings(at: Array(path.dropFirst()), in: $0) } ?? []
        }
        switch value {
        case let string as String: return [string]
        case let strings as [String]: return strings
        case let data as Data: return [hex(data)]
        case let number as NSNumber: return [number.stringValue]
        default: return []
        }
    }

    private static func hex32(_ value: Any?) -> String? {
        (value as? NSNumber).map { String(format: "%08X", $0.uint32Value) }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
