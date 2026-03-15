import Foundation
import Security

private let SecAttrAccessGroup = kSecAttrAccessGroup as String
private let SecAttrAccessible = kSecAttrAccessible as String
private let SecAttrAccount = kSecAttrAccount as String
private let SecAttrGeneric = kSecAttrGeneric as String
private let SecAttrService = kSecAttrService as String
private let SecAttrSynchronizable = kSecAttrSynchronizable as String
private let SecAttrSynchronizableAny = kSecAttrSynchronizableAny as String

private let SecClass = kSecClass as String
private let SecMatchLimit = kSecMatchLimit as String
private let SecReturnAttributes = kSecReturnAttributes as String
private let SecReturnData = kSecReturnData as String
private let SecReturnPersistentRef = kSecReturnPersistentRef as String
private let SecValueData = kSecValueData as String

/// KeychainWrapper is a class to help make Keychain access in Swift more straightforward. It is designed to make accessing the Keychain services more like using NSUserDefaults, which is much more familiar to people.
final class BaseKeychain: Keychain {
    enum Config {
        static let defaultAccessibilityLevel = KeychainItemAccessibility.afterFirstUnlock
        static let defaultSynchronizable = true
    }

    fileprivate enum KeychainSynchronizable {
        case any
        case yes
        case no
    }

    private struct EncodableWrapper<T: Encodable>: Encodable {
        let v: T
    }

    private struct DecodableWrapper<T: Decodable>: Decodable {
        let v: T
    }

    /// ServiceName is used for the kSecAttrService property to uniquely identify this keychain accessor. If no service name is specified, KeychainWrapper will default to using the bundleIdentifier.
    private(set) var serviceName: String

    /// AccessGroup is used for the kSecAttrAccessGroup property to identify which Keychain Access Group this entry belongs to. This allows you to use the KeychainWrapper with shared keychain access between different applications.
    private(set) var accessGroup: String?

    private let defaultSynchronizable: Bool
    private let defaultAccessibilityLevel: KeychainItemAccessibility

    private static let defaultServiceName: String = {
        Bundle.main.bundleIdentifier ?? "SwiftBaseKeychain"
    }()

    init(
        serviceName: String = BaseKeychain.defaultServiceName,
        synchronizable: Bool = Config.defaultSynchronizable,
        accessibilityLevel: KeychainItemAccessibility = Config.defaultAccessibilityLevel,
        accessGroup: String? = nil
    ) {
        self.serviceName = serviceName
        defaultSynchronizable = synchronizable
        defaultAccessibilityLevel = accessibilityLevel
        self.accessGroup = accessGroup
    }

    // MARK: - Public Methods

    func allKeys() -> Set<String> {
        var query: [String: Any] = [SecClass: kSecClassGenericPassword]

        query[SecAttrService] = serviceName
        query[SecMatchLimit] = kSecMatchLimitAll
        query[SecReturnAttributes] = kCFBooleanTrue
        query[SecReturnData] = kCFBooleanTrue
        query[SecAttrSynchronizable] = kSecAttrSynchronizableAny

        if let accessGroup = accessGroup {
            query[SecAttrAccessGroup] = accessGroup
        }

        var result: AnyObject?

        let lastResultCode = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0))
        }

        var keys = Set<String>()
        if lastResultCode == noErr {
            guard let array = result as? [[String: Any]] else {
                return keys
            }

            for item in array {
                if let keyData = item[SecAttrAccount] as? Data,
                   let key = String(data: keyData, encoding: .utf8)
                {
                    keys.update(with: key)
                }
            }
        }

        return keys
    }

    func hasValue(forKey key: String) -> Result<Bool, KeychainError> {
        getData(forKey: key).map { $0 != nil }
    }

    func accessibilityOfKey(_ key: String) -> Result<KeychainItemAccessibility, KeychainError> {
        var keychainQueryDictionary = setupKeychainQueryDictionary(
            forKey: key,
            synchronizable: defaultSynchronizable.keychainFlag,
            withAccessibility: defaultAccessibilityLevel
        )
        var result: AnyObject?

        // Remove accessibility attribute
        keychainQueryDictionary.removeValue(forKey: SecAttrAccessible)

        // Limit search results to one
        keychainQueryDictionary[SecMatchLimit] = kSecMatchLimitOne

        // Specify we want SecAttrAccessible returned
        keychainQueryDictionary[SecReturnAttributes] = kCFBooleanTrue

        // Search
        let status = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(keychainQueryDictionary as CFDictionary, UnsafeMutablePointer($0))
        }

        if status == errSecSuccess {
            if let resultsDictionary = result as? [String: AnyObject],
               let accessibilityAttrValue = resultsDictionary[SecAttrAccessible] as? String,
               let mappedValue = KeychainItemAccessibility.accessibilityForAttributeValue(accessibilityAttrValue as CFString)
            {
                return .success(mappedValue)
            }
        }

        return .failure(.darwinError(status))
    }

    // MARK: Public Getters

    func getData(forKey key: String) -> Result<Data?, KeychainError> {
        var keychainQueryDictionary = setupKeychainQueryDictionary(
            forKey: key,
            synchronizable: defaultSynchronizable.keychainFlag,
            withAccessibility: defaultAccessibilityLevel
        )
        var result: AnyObject?

        // Limit search results to one
        keychainQueryDictionary[SecMatchLimit] = kSecMatchLimitOne

        // Specify we want Data/CFData returned
        keychainQueryDictionary[SecReturnData] = kCFBooleanTrue

        // Search
        let status = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(keychainQueryDictionary as CFDictionary, UnsafeMutablePointer($0))
        }

        if status == errSecSuccess {
            return .success(result as? Data)
        } else if status == errSecItemNotFound {
            return .success(nil)
        }

        return .failure(.darwinError(status))
    }

    func getValue<T: Decodable>(_: T.Type, forKey key: String) -> Result<T?, KeychainError> {
        switch getData(forKey: key) {
        case let .success(data):
            guard let data = data else { return .success(nil) }
            let decoder = JSONDecoder()
            do {
                let decoded = try decoder.decode(DecodableWrapper<T>.self, from: data)
                return .success(decoded.v)
            } catch {
                return .failure(.codingError(error))
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    // MARK: Public Setters

    @discardableResult func setData(_ value: Data, forKey key: String) -> Result<Void, KeychainError> {
        var keychainQueryDictionary: [String: Any] = setupKeychainQueryDictionary(
            forKey: key,
            synchronizable: defaultSynchronizable.keychainFlag,
            withAccessibility: defaultAccessibilityLevel
        )

        keychainQueryDictionary[SecValueData] = value

        keychainQueryDictionary[SecAttrAccessible] = defaultAccessibilityLevel.keychainAttrValue

        let status = SecItemAdd(keychainQueryDictionary as CFDictionary, nil)

        if status == errSecSuccess {
            return .success(())
        } else if status == errSecDuplicateItem {
            return update(value, forKey: key)
        } else {
            return .failure(.darwinError(status))
        }
    }

    @discardableResult func setValue<T: Encodable>(_ maybeValue: T?, forKey key: String) -> Result<Void, KeychainError> {
        if let value = maybeValue {
            let wrapper = EncodableWrapper(v: value)
            let encoder = JSONEncoder()
            do {
                let encoded = try encoder.encode(wrapper)
                return setData(encoded, forKey: key)
            } catch {
                return .failure(.codingError(error))
            }
        } else {
            return removeObject(forKey: key)
        }
    }

    private func removeObject(
        forKey key: String,
        withAccessibility accessibility: KeychainItemAccessibility? = nil
    ) -> Result<Void, KeychainError> {
        let keychainQueryDictionary: [String: Any] = setupKeychainQueryDictionary(
            forKey: key,
            synchronizable: .any,
            withAccessibility: accessibility ?? defaultAccessibilityLevel
        )

        // Delete
        let status = SecItemDelete(keychainQueryDictionary as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return .success(())
        } else {
            return .failure(.darwinError(status))
        }
    }

    @discardableResult func removeObject(forKey key: String) -> Result<Void, KeychainError> {
        removeObject(forKey: key, withAccessibility: defaultAccessibilityLevel)
    }

    /// Remove all keychain data added through KeychainWrapper. This will only delete items matching the currnt ServiceName and AccessGroup if one is set.
    func removeAllKeys() -> Result<Void, KeychainError> {
        // Setup dictionary to access keychain and specify we are using a generic password (rather than a certificate, internet password, etc)
        var keychainQueryDictionary: [String: Any] = [SecClass: kSecClassGenericPassword]

        // Uniquely identify this keychain accessor
        keychainQueryDictionary[SecAttrService] = serviceName
        keychainQueryDictionary[SecAttrSynchronizable] = SecAttrSynchronizableAny

        // Set the keychain access group if defined
        if let accessGroup = self.accessGroup {
            keychainQueryDictionary[SecAttrAccessGroup] = accessGroup
        }

        let status = SecItemDelete(keychainQueryDictionary as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return .success(())
        } else {
            return .failure(.darwinError(status))
        }
    }

    /// Remove all keychain data, including data not added through keychain wrapper.
    ///
    /// - Warning: This may remove custom keychain entries you did not add via SwiftKeychainWrapper.
    ///
    static func wipeKeychain() {
        deleteKeychainSecClass(kSecClassGenericPassword) // Generic password items
        deleteKeychainSecClass(kSecClassInternetPassword) // Internet password items
        deleteKeychainSecClass(kSecClassCertificate) // Certificate items
        deleteKeychainSecClass(kSecClassKey) // Cryptographic key items
        deleteKeychainSecClass(kSecClassIdentity) // Identity items
    }

    // MARK: - Private Methods

    /// Remove all items for a given Keychain Item Class
    ///
    ///
    @discardableResult private class func deleteKeychainSecClass(_ secClass: AnyObject) -> Result<Void, KeychainError> {
        let query = [SecClass: secClass]
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess {
            return .success(())
        } else {
            return .failure(.darwinError(status))
        }
    }

    /// Update existing data associated with a specified key name. The existing data will be overwritten by the new data
    private func update(_ value: Data, forKey key: String) -> Result<Void, KeychainError> {
        var keychainQueryDictionary: [String: Any] = setupKeychainQueryDictionary(
            forKey: key,
            synchronizable: defaultSynchronizable.keychainFlag,
            withAccessibility: defaultAccessibilityLevel
        )
        let updateDictionary = [SecValueData: value]

        keychainQueryDictionary[SecAttrAccessible] = defaultAccessibilityLevel.keychainAttrValue

        // Update
        let status = SecItemUpdate(keychainQueryDictionary as CFDictionary, updateDictionary as CFDictionary)

        if status == errSecSuccess {
            return .success(())
        } else {
            return .failure(.darwinError(status))
        }
    }

    private func setupKeychainQueryDictionary(
        forKey key: String,
        synchronizable: KeychainSynchronizable,
        withAccessibility accessibility: KeychainItemAccessibility
    ) -> [String: Any] {
        // Setup default access as generic password (rather than a certificate, internet password, etc)
        var keychainQueryDictionary: [String: Any] = [SecClass: kSecClassGenericPassword]

        // Uniquely identify this keychain accessor
        keychainQueryDictionary[SecAttrService] = serviceName

        keychainQueryDictionary[SecAttrAccessible] = accessibility.keychainAttrValue

        // Set the keychain access group if defined
        if let accessGroup = self.accessGroup {
            keychainQueryDictionary[SecAttrAccessGroup] = accessGroup
        }

        // Uniquely identify the account who will be accessing the keychain
        let encodedIdentifier: Data? = key.data(using: String.Encoding.utf8)

        keychainQueryDictionary[SecAttrGeneric] = encodedIdentifier

        keychainQueryDictionary[SecAttrAccount] = encodedIdentifier

        keychainQueryDictionary[SecAttrSynchronizable] = { () -> Any in
            switch synchronizable {
            case .yes: return true
            case .no: return false
            case .any: return SecAttrSynchronizableAny
            }
        }()

        return keychainQueryDictionary
    }
}

private extension Bool {
    var keychainFlag: BaseKeychain.KeychainSynchronizable {
        switch self {
        case true: return .yes
        case false: return .no
        }
    }
}

extension BaseKeychain: KeyValueStorage {
    func getValue<T: Codable>(_: T.Type, forKey key: String) -> T? {
        getValue(T.self, forKey: key, defaultValue: nil, reportError: true)
    }

    func getValue<T: Codable>(_: T.Type, forKey key: String, defaultValue: T?, reportError: Bool) -> T? {
        let result = getValue(T.self, forKey: key) as Result<T?, KeychainError>

        if reportError, case let .failure(error) = result {
            assertionFailure("Failed to set persisted value for key: \(key), error: \(error.localizedDescription)")
        }

        return try? result.get() ?? defaultValue
    }

    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String) {
        setValue(maybeValue, forKey: key, reportError: true)
    }

    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String, reportError: Bool) {
        let result = setValue(maybeValue, forKey: key) as Result<Void, KeychainError>

        if reportError, case let .failure(error) = result {
            assertionFailure("Failed to set persisted value.for key: \(key), error: \(error.localizedDescription)")
        }
    }
}
