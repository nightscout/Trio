//
//  UserDefaultsExtension.swift
//  FreeAPS
//
//  Created by Marvin Polscheit on 26.05.24.
//

import Foundation
import CoreData

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
