//
//  WatchStateSnapshot.swift
//  Trio
//
//  Created by Cengiz Deniz on 18.04.25.
//
import Foundation

struct WatchStateSnapshot {
    let date: Date
    let payload: [String: Any]

    init?(from dictionary: [String: Any]) {
        guard let timestamp = dictionary[WatchMessageKeys.date] as? TimeInterval,
              let payload = dictionary[WatchMessageKeys.watchState] as? [String: Any]
        else {
            return nil
        }

        date = Date(timeIntervalSince1970: timestamp)
        self.payload = payload
    }

    func toDictionary() -> [String: Any] {
        [
            WatchMessageKeys.date: date.timeIntervalSince1970,
            WatchMessageKeys.watchState: payload
        ]
    }

    static func saveLatestDateToDisk(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "WatchStateSnapshot.latest")
    }

    static func loadLatestDateFromDisk() -> Date {
        let interval = UserDefaults.standard.double(forKey: "WatchStateSnapshot.latest")
        return Date(timeIntervalSince1970: interval)
    }
}
