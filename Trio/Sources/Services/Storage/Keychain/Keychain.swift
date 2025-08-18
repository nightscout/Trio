import Foundation

enum KeychainError: Error {
    case darwinError(OSStatus)
    case codingError(Error)
}

protocol Keychain: KeyValueStorage {
    func allKeys() -> Set<String>
    func hasValue(forKey key: String) -> Result<Bool, KeychainError>
    func accessibilityOfKey(_ key: String) -> Result<KeychainItemAccessibility, KeychainError>

    func getData(forKey key: String) -> Result<Data?, KeychainError>
    func getValue<T: Decodable>(_ type: T.Type, forKey key: String) -> Result<T?, KeychainError>

    @discardableResult func setData(_ value: Data, forKey key: String) -> Result<Void, KeychainError>
    @discardableResult func setValue<T: Encodable>(_ maybeValue: T?, forKey key: String) -> Result<Void, KeychainError>

    @discardableResult func removeObject(forKey key: String) -> Result<Void, KeychainError>
    @discardableResult func removeAllKeys() -> Result<Void, KeychainError>

    static func wipeKeychain()
}
