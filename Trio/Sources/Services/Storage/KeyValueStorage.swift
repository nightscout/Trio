//
// Trio
// KeyValueStorage.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

protocol KeyValueStorage: AnyObject {
    func getValue<T: Codable>(_: T.Type, forKey key: String) -> T?
    func getValue<T: Codable>(_: T.Type, forKey key: String, defaultValue: T?, reportError: Bool) -> T?

    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String)
    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String, reportError: Bool)
}
