// Trio
// KeyValueStorage.swift
// Created by Ivan Valkou on 2021-02-02.

import Foundation

protocol KeyValueStorage: AnyObject {
    func getValue<T: Codable>(_: T.Type, forKey key: String) -> T?
    func getValue<T: Codable>(_: T.Type, forKey key: String, defaultValue: T?, reportError: Bool) -> T?

    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String)
    func setValue<T: Codable>(_ maybeValue: T?, forKey key: String, reportError: Bool)
}
