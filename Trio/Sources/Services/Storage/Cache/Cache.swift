// Trio
// Cache.swift
// Created by Ivan Valkou on 2021-02-02.

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
