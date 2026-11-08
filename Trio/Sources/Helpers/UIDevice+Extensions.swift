import SwiftUI

extension UIDevice {
    var getDeviceId: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        func mapToDevice(identifier: String) -> String {
            switch identifier {
            case "iPhone10,4":
                return "iPhone 8"
            case "iPhone10,5":
                return "iPhone 8 Plus"
            case "iPhone10,6":
                return "iPhone X"

            case "iPhone11,2":
                return "iPhone Xs"
            case "iPhone11,8":
                return "iPhone XR"

            case "iPhone12,1":
                return "iPhone 11"
            case "iPhone12,5":
                return "iPhone 11 Pro Max"
            case "iPhone12,8":
                return "iPhone SE (2nd Gen)"

            case "iPhone13,1":
                return "iPhone 12 mini"
            case "iPhone13,2":
                return "iPhone 12"
            case "iPhone13,3":
                return "iPhone 12 Pro"
            case "iPhone13,4":
                return "iPhone 12 Pro Max"

            case "iPhone14,2":
                return "iPhone 13 Pro"
            case "iPhone14,3":
                return "iPhone 13 Pro Max"
            case "iPhone14,4":
                return "iPhone 13 mini"
            case "iPhone14,5":
                return "iPhone 13"
            case "iPhone14,6":
                return "iPhone SE (3rd Gen)"
            case "iPhone14,7":
                return "iPhone 14"
            case "iPhone14,8":
                return "iPhone 14 Plus"

            case "iPhone15,2":
                return "iPhone 14 Pro"
            case "iPhone15,3":
                return "iPhone 14 Pro Max"

            default:
                return identifier
            }
        }

        return mapToDevice(identifier: identifier)
    }

    /// Marketing name of the device, e.g. "iPhone 15 Pro". Falls back to the model identifier
    /// (e.g. "iPhone19,1") for models not in the list.
    var marketingName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        var identifier = withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        if let simulatorIdentifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            identifier = simulatorIdentifier
        }

        let names: [String: String] = [
            "iPhone10,1": "iPhone 8",
            "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus",
            "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X",
            "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS",
            "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR",
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone12,8": "iPhone SE (2nd generation)",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,6": "iPhone SE (3rd generation)",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,5": "iPhone 16e",
            "iPhone18,3": "iPhone 17",
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,4": "iPhone Air",
            "iPhone18,5": "iPhone 17e",
            "iPhone19,2": "iPhone 18 Pro",
            "iPhone19,3": "iPhone 18 Pro Max",
            "iPhone19,7": "iPhone 18 Pro Max",
            "iPhone19,4": "iPhone Duo"
        ]

        return names[identifier] ?? identifier
    }

    var getOSInfo: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return String(os.majorVersion) + "." + String(os.minorVersion) + "." + String(os.patchVersion)
    }
}
