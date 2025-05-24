//
// Trio
// UserDefaultsExtension.swift
// Created by Marvin Polscheit on 2024-05-26.
// Last edited by Marvin Polscheit on 2024-05-26.
// Most contributions by Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreData
import Foundation

extension UserDefaults {
    private enum Keys {
        static let lastHistoryToken = "lastHistoryToken"
    }

    var lastHistoryToken: NSPersistentHistoryToken? {
        get {
            guard let data = data(forKey: Keys.lastHistoryToken) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        set {
            guard let token = newValue else {
                removeObject(forKey: Keys.lastHistoryToken)
                return
            }
            let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            set(data, forKey: Keys.lastHistoryToken)
        }
    }
}
