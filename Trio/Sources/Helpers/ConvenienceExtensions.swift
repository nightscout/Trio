import UIKit

protocol Occupiable {
    var isEmpty: Bool { get }
    var isNotEmpty: Bool { get }

    var nonEmpty: Self? { get }
}

// Give a default implementation of isNotEmpty, so conformance only requires one implementation
extension Occupiable {
    var isNotEmpty: Bool {
        !isEmpty
    }

    var nonEmpty: Self? {
        isEmpty ? nil : self
    }
}

extension String: Occupiable {}

extension Array: Occupiable {}
extension ArraySlice: Occupiable {}
extension CGRect: Occupiable {}
extension Data: Occupiable {}
extension Dictionary: Occupiable {}
extension Set: Occupiable {}

// Extend the idea of occupiability to optionals. Specifically, optionals wrapping occupiable things.
extension Optional where Wrapped: Occupiable {
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case let .some(value):
            return value.isEmpty
        }
    }

    var isNotNilNotEmpty: Bool {
        !isNilOrEmpty
    }
}
