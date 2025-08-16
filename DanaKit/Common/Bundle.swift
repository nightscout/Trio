import Foundation

extension Bundle {
    var bundleDisplayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
    }
}
