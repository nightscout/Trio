@propertyWrapper public struct JavascriptOptional<T> {
    public var wrappedValue: T?

    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
}

extension JavascriptOptional: Codable where T: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(T.self) {
            wrappedValue = value
        } else if (try? container.decode(Bool.self)) == false {
            wrappedValue = nil
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected number or false")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = wrappedValue {
            try container.encode(value)
        } else {
            try container.encode(false)
        }
    }
}
