import Foundation

enum CacheError: Error {
    case codingError(Error)
}

protocol Cache: KeyValueStorage {}

struct EncodableWrapper<T: Encodable>: Encodable {
    let v: T
}

struct DecodableWrapper<T: Decodable>: Decodable {
    let v: T
}
