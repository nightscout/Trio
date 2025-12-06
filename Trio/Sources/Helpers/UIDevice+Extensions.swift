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

    var getOSInfo: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return String(os.majorVersion) + "." + String(os.minorVersion) + "." + String(os.patchVersion)
    }
}
