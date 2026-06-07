//
//  WatchStateSnapshot.swift
//  Trio
//
//  Created by Cengiz Deniz on 18.04.25.
//
import Foundation

enum WatchStateSnapshot {
    private static let storageKey = "WatchStateSnapshot.latest"

    static func saveLatestDateToDisk(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: storageKey)
    }

    static func loadLatestDateFromDisk() -> Date {
        let interval = UserDefaults.standard.double(forKey: storageKey)
        return Date(timeIntervalSince1970: interval)
    }
}
