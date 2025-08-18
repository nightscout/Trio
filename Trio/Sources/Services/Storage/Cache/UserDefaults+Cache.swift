import Foundation

extension UserDefaults: Cache {
    func getValue<T: Codable>(_: T.Type, forKey key: String) -> T? {
        getValue(T.self, forKey: key, defaultValue: nil, reportError: true)
    }

    func getValue<T: Codable>(_: T.Type, forKey key: String, defaultValue: T?, reportError: Bool) -> T? {
        guard let data = self.data(forKey: key) else { return defaultValue }
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(DecodableWrapper<T>.self, from: data)
            return decoded.v
        } catch {
            if reportError {
                assertionFailure("Failed to get persisted value for key: \(key), error: \(error.localizedDescription)")
            }
        }
        return defaultValue
    }

    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String) {
        setValue(maybeValue, forKey: key, reportError: true)
    }

    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String, reportError: Bool) {
        if let value = maybeValue {
            let wrapper = EncodableWrapper(v: value)
            let encoder = JSONEncoder()
            do {
                let encoded = try encoder.encode(wrapper)
                set(encoded, forKey: key)
            } catch {
                if reportError {
                    assertionFailure("Failed to set persisted value.for key: \(key), error: \(error.localizedDescription)")
                }
            }
        } else {
            removeObject(forKey: key)
        }
    }
}
