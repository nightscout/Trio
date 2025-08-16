import Foundation

protocol IdentifiableClass: AnyObject {
    static var className: String { get }
}

extension IdentifiableClass {
    static var className: String {
        NSStringFromClass(self).components(separatedBy: ".").last!
    }
}
