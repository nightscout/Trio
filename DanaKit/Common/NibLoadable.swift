import UIKit

protocol NibLoadable: IdentifiableClass {
    static func nib() -> UINib
}

extension NibLoadable {
    static func nib() -> UINib {
        UINib(nibName: className, bundle: Bundle(for: self))
    }
}
