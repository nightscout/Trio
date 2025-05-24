//
// Trio
// Cache.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

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
