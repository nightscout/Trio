import Foundation
import SwiftUI
import Testing
@testable import Trio_Watch_App

/// The compact glucose trace the phone sends with every state, and how the watch shows it.
@Suite("Watch glucose trace") struct WatchGlucoseTraceTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_123)

    /// A day of readings every `interval` seconds up to `now`, oldest first.
    static func day(every interval: TimeInterval) -> [WatchGlucoseTrace.Reading] {
        stride(from: now.timeIntervalSince1970 - 24 * 3600, through: now.timeIntervalSince1970, by: interval).map {
            WatchGlucoseTrace.Reading(date: Date(timeIntervalSince1970: $0), glucose: Int($0) % 300 + 40)
        }
    }

    @Test("A day of readings comes back as it went") func roundTrip() throws {
        let readings = Self.day(every: 300)
        #expect(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode(readings)) == readings)
    }

    @Test("Readings out of order are sorted, times rounded to the second") func sortedAndRounded() throws {
        let readings = [
            WatchGlucoseTrace.Reading(date: Date(timeIntervalSince1970: 1000.4), glucose: 120),
            WatchGlucoseTrace.Reading(date: Date(timeIntervalSince1970: 700.6), glucose: 110)
        ]
        let decoded = try #require(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode(readings)))
        #expect(decoded.map(\.date.timeIntervalSince1970) == [701, 1000])
        #expect(decoded.map(\.glucose) == [110, 120])
    }

    @Test("The phone's colors travel with the readings, or not at all") func colorsRoundTrip() throws {
        let colored = Self.day(every: 300).enumerated().map { index, reading in
            WatchGlucoseTrace.Reading(date: reading.date, glucose: reading.glucose, color: index * 0x010203 & 0xFFFFFF)
        }
        #expect(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode(colored)) == colored)
        // one reading without a color: none go, the watch colors by the range
        var partly = colored
        partly[3] = WatchGlucoseTrace.Reading(date: colored[3].date, glucose: colored[3].glucose)
        #expect(WatchGlucoseTrace.encode(partly)[WatchGlucoseTrace.colorsKey] == nil)
        // a dynamic day of a 5-minute CGM stays small
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: WatchGlucoseTrace.encode(colored),
            format: .binary,
            options: 0
        ).count
        #expect(bytes < 4000)
    }

    @Test("No readings, and what isn't a trace") func emptyAndInvalid() {
        #expect(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode([])) == [])
        #expect(WatchGlucoseTrace.decode([:]) == nil)
        #expect(WatchGlucoseTrace.decode([
            WatchGlucoseTrace.startKey: 0,
            WatchGlucoseTrace.timesKey: [0, 300],
            WatchGlucoseTrace.valuesKey: [100]
        ]) == nil)
    }

    @Test("Small enough to send the whole day every time") func size() throws {
        func bytes(_ readings: [WatchGlucoseTrace.Reading]) throws -> Int {
            try PropertyListSerialization.data(
                fromPropertyList: WatchGlucoseTrace.encode(readings),
                format: .binary,
                options: 0
            ).count
        }
        // a 5-minute CGM and a 1-minute one
        #expect(try bytes(Self.day(every: 300)) < 2000)
        #expect(try bytes(Self.day(every: 60)) < 8000)
    }

    /// The colors a state from the phone gives its readings on the watch; `sent`, the phone's colors.
    static func colors(_ glucose: [Int], scheme: GlucoseColorScheme, sent: [Int]? = nil) -> [Color.Resolved] {
        let state = WatchState()
        let now = Date()
        let readings = glucose.enumerated().map { index, value in
            WatchGlucoseTrace.Reading(
                date: now.addingTimeInterval(Double(index - glucose.count) * 300),
                glucose: value,
                color: sent?[index]
            )
        }
        let payload: [String: Any] = [
            WatchMessageKeys.date: now.timeIntervalSince1970,
            WatchMessageKeys.glucoseTrace: WatchGlucoseTrace.encode(readings),
            WatchMessageKeys.glucoseRangeLow: 70.0,
            WatchMessageKeys.glucoseRangeHigh: 180.0,
            WatchMessageKeys.glucoseRangeTarget: 100.0,
            WatchMessageKeys.glucoseColorScheme: scheme.rawValue
        ]
        state.acceptWatchStatePayload([WatchMessageKeys.watchState: payload])
        return state.glucoseValues.map { $0.color.resolve(in: EnvironmentValues()) }
    }

    static func resolved(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }

    @Test("Colored as the phone colors them, by the range it sends") func staticColors() {
        #expect(Self.colors([60, 120, 200], scheme: .staticColor) == [
            Self.resolved(.staticLow), Self.resolved(.staticInRange), Self.resolved(.staticHigh)
        ])
    }

    @Test("The dynamic scheme shows the colors the phone computed") func dynamicColors() {
        let sent = [0xFF0000, 0x00FF00, 0x8000FF]
        #expect(Self.colors([55, 100, 220], scheme: .dynamicColor, sent: sent) == sent.map {
            Self.resolved(WatchState.color(rgb: $0))
        })
    }

    @Test("A state from the phone shows its readings in its units") func appliedInUnits() throws {
        let state = WatchState()
        let readings = [
            WatchGlucoseTrace.Reading(date: Date().addingTimeInterval(-300), glucose: 100),
            WatchGlucoseTrace.Reading(date: Date(), glucose: 126)
        ]
        let payload: [String: Any] = [
            WatchMessageKeys.date: Date().timeIntervalSince1970,
            WatchMessageKeys.units: "mmol/L",
            WatchMessageKeys.glucoseTrace: WatchGlucoseTrace.encode(readings)
        ]
        #expect(state.acceptWatchStatePayload([WatchMessageKeys.watchState: payload]))
        #expect(state.glucoseValues.map(\.glucose) == [5.6, 7.0])
    }
}
