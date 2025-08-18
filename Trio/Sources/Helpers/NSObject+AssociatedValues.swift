import Foundation

struct AssociationKey<Value> {
    fileprivate let address: UnsafeRawPointer
    fileprivate let `default`: Value!
    /// Create an ObjC association key from a `StaticString`.
    ///
    /// - precondition: `key` has a pointer representation.
    ///
    /// - parameters:
    ///   - default: The default value, or `nil` to trap on undefined value. It is
    ///              ignored if `Value` is an optional.
    init(_ key: StaticString, default: Value? = nil) {
        assert(key.hasPointerRepresentation, "AssociationKey.init key has no hasPointerRepresentation")
        address = UnsafeRawPointer(key.utf8Start)
        self.default = `default`
    }
}

struct Associations<Base: AnyObject> {
    private let base: Base

    init(_ base: Base) {
        self.base = base
    }
}

extension NSObjectProtocol {
    @nonobjc var associations: Associations<Self> {
        Associations(self)
    }

    func getAssociatedValue<T>(forKey key: StaticString = #function) -> T? {
        associations.value(forKey: AssociationKey<T?>(key))
    }

    func setAssociatedValue<T>(forKey key: StaticString = #function, value: T?) {
        associations.setValue(value, forKey: AssociationKey<T?>(key))
    }
}

extension Associations {
    /// Retrieve the associated value for the specified key.
    ///
    /// - parameters:
    ///   - key: The key.
    ///
    /// - returns: The associated value, or the default value if no value has been
    ///            associated with the key.
    func value<Value>(forKey key: AssociationKey<Value>) -> Value {
        (objc_getAssociatedObject(base, key.address) as! Value?) ?? key.default
    }

    /// Retrieve the associated value for the specified key.
    ///
    /// - parameters:
    ///   - key: The key.
    ///
    /// - returns: The associated value, or `nil` if no value is associated with
    ///            the key.
    func value<Value>(forKey key: AssociationKey<Value?>) -> Value? {
        objc_getAssociatedObject(base, key.address) as! Value?
    }

    /// Set the associated value for the specified key.
    ///
    /// - parameters:
    ///   - value: The value to be associated.
    ///   - key: The key.
    func setValue<Value>(_ value: Value, forKey key: AssociationKey<Value>) {
        objc_setAssociatedObject(base, key.address, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Set the associated value for the specified key.
    ///
    /// - parameters:
    ///   - value: The value to be associated.
    ///   - key: The key.
    func setValue<Value>(_ value: Value?, forKey key: AssociationKey<Value?>) {
        objc_setAssociatedObject(base, key.address, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
