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

    @Test("Colored as the phone colors them") func coloring() {
        func resolved(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }
        var coloring = WatchGlucoseColoring()
        coloring.low = 70
        coloring.high = 180
        coloring.target = 100

        let red = resolved(Color(hue: 0.0 / 360.0, saturation: 0.6, brightness: 0.9))
        let green = resolved(Color(hue: 120.0 / 360.0, saturation: 0.6, brightness: 0.9))
        let violet = resolved(Color(hue: 270.0 / 360.0, saturation: 0.6, brightness: 0.9))
        #expect(resolved(coloring.color(70)) == red)
        #expect(resolved(coloring.color(120)) == green)
        #expect(resolved(coloring.color(180)) == violet)

        // the dynamic scheme ramps from 55 through the target to 220
        coloring.isDynamic = true
        #expect(resolved(coloring.color(55)) == red)
        #expect(resolved(coloring.color(100)) == green)
        #expect(resolved(coloring.color(220)) == violet)
        #expect(resolved(coloring.color(70)) != red)
    }

    @Test("The range and scheme come from the phone's state") func coloringFromPayload() {
        let coloring = WatchGlucoseColoring([
            WatchMessageKeys.glucoseRangeLow: 80.0,
            WatchMessageKeys.glucoseRangeHigh: 160.0,
            WatchMessageKeys.glucoseRangeTarget: 110.0,
            WatchMessageKeys.glucoseColorScheme: "dynamicColor"
        ])
        #expect(coloring.low == 80)
        #expect(coloring.high == 160)
        #expect(coloring.target == 110)
        #expect(coloring.isDynamic)
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
