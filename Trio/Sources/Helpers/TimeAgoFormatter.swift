//
//  TimeAgoFormatter.swift
//  Trio
//
//  Created by Cengiz Deniz on 21.05.25.
//
import Foundation

enum TimeAgoFormatter {
    /// Returns a user-facing string for how many minutes ago the given date occurred,
    /// formatted with non-breaking spaces and localized abbreviation.
    ///
    /// - Parameter date: The past `Date` to calculate elapsed time from.
    /// - Returns: A formatted string like `"< 1 m"` or `"2 m"`. Returns `"--"` if the date is `nil`.
    static func minutesAgo(from date: Date?) -> String {
        guard let date = date else {
            return "--"
        }

        let secondsAgo = -date.timeIntervalSinceNow
        let minutesAgo = Int(floor(secondsAgo / 60))

        if minutesAgo >= 1 {
            let minuteString = Formatter.timaAgoFormatter.string(for: Double(minutesAgo)) ?? "\(minutesAgo)"
            return minuteString + "\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
        } else {
            return "<" + "\u{00A0}" + "1" + "\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
        }
    }

    // Calculates the floored integer value of how many full minutes ago the given date occurred.
    ///
    /// - Parameter date: The past `Date` to compare against the current time.
    /// - Returns: An integer representing the number of full minutes since the given date.
    ///            Returns `Int.max` if the date is `nil`.
    static func minutesAgoValue(from date: Date?) -> Int {
        guard let date = date else {
            return Int.max
        }
        return Int(floor(-date.timeIntervalSinceNow / 60))
    }
}
