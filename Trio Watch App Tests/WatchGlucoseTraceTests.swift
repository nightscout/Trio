import Foundation
import SwiftUI
import Testing
@testable import Trio_Watch_App

/// The compact glucose trace the phone sends with every state, and how the watch shows it.
@Suite("Watch glucose trace") struct WatchGlucoseTraceTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_123)

    /// A day of readings every `interval` seconds up to `now`, oldest first, in mg/dL.
    static func day(every interval: TimeInterval) -> [WatchGlucoseTrace.Reading] {
        stride(from: now.timeIntervalSince1970 - 24 * 3600, through: now.timeIntervalSince1970, by: interval).map {
            let glucose = Int($0) % 300 + 40
            return WatchGlucoseTrace.Reading(
                date: Date(timeIntervalSince1970: $0),
                glucose: Double(glucose),
                color: glucose * 0x010203 & 0xFFFFFF
            )
        }
    }

    @Test("A day of readings comes back as it went") func roundTrip() throws {
        let readings = Self.day(every: 300)
        #expect(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode(readings, scale: 1)) == readings)
    }

    @Test("mmol/L keeps the phone's one decimal") func mmol() throws {
        let readings = [5.6, 7.0, 3.9, 12.4].enumerated().map { index, value in
            WatchGlucoseTrace.Reading(date: Self.now.addingTimeInterval(Double(index) * 300), glucose: value, color: 0xFFFFFF)
        }
        let decoded = try #require(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode(readings, scale: 10)))
        #expect(decoded.map(\.glucose) == [5.6, 7.0, 3.9, 12.4])
    }

    @Test("Readings out of order are sorted, times rounded to the second") func sortedAndRounded() throws {
        let readings = [
            WatchGlucoseTrace.Reading(date: Date(timeIntervalSince1970: 1000.4), glucose: 120, color: 0x00FF00),
            WatchGlucoseTrace.Reading(date: Date(timeIntervalSince1970: 700.6), glucose: 110, color: 0xFF0000)
        ]
        let decoded = try #require(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode(readings, scale: 1)))
        #expect(decoded.map(\.date.timeIntervalSince1970) == [701, 1000])
        #expect(decoded.map(\.glucose) == [110, 120])
        #expect(decoded.map(\.color) == [0xFF0000, 0x00FF00])
    }

    @Test("No readings, and what isn't a trace") func emptyAndInvalid() {
        #expect(WatchGlucoseTrace.decode(WatchGlucoseTrace.encode([], scale: 1)) == [])
        #expect(WatchGlucoseTrace.decode([:]) == nil)
        #expect(WatchGlucoseTrace.decode([
            WatchGlucoseTrace.startKey: 0,
            WatchGlucoseTrace.timesKey: [0, 300],
            WatchGlucoseTrace.valuesKey: [100, 2],
            WatchGlucoseTrace.colorsKey: [0xFFFFFF],
            WatchGlucoseTrace.scaleKey: 1
        ]) == nil)
    }

    @Test("The phone's hex colors as integers") func hexColors() {
        #expect(WatchGlucoseTrace.rgb(hex: "#4CD964") == 0x4CD964)
        #expect(WatchGlucoseTrace.rgb(hex: "nonsense") == 0xFFFFFF)
    }

    @Test("Small enough to send the whole day every time") func size() throws {
        func bytes(_ readings: [WatchGlucoseTrace.Reading]) throws -> Int {
            try PropertyListSerialization.data(
                fromPropertyList: WatchGlucoseTrace.encode(readings, scale: 1),
                format: .binary,
                options: 0
            ).count
        }
        // a 5-minute CGM and a 1-minute one
        #expect(try bytes(Self.day(every: 300)) < 3000)
        #expect(try bytes(Self.day(every: 60)) < 12000)
    }

    @Test("A state from the phone shows its readings as the phone shows them") func applied() throws {
        let state = WatchState()
        let readings = [
            WatchGlucoseTrace.Reading(date: Date().addingTimeInterval(-300), glucose: 5.6, color: 0x4CD964),
            WatchGlucoseTrace.Reading(date: Date(), glucose: 7.0, color: 0xFF3B30)
        ]
        let payload: [String: Any] = [
            WatchMessageKeys.date: Date().timeIntervalSince1970,
            WatchMessageKeys.units: "mmol/L",
            WatchMessageKeys.glucoseTrace: WatchGlucoseTrace.encode(readings, scale: 10)
        ]
        #expect(state.acceptWatchStatePayload([WatchMessageKeys.watchState: payload]))
        #expect(state.glucoseValues.map(\.glucose) == [5.6, 7.0])
        func resolved(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }
        #expect(state.glucoseValues.map { resolved($0.color) } == [
            resolved(WatchState.color(rgb: 0x4CD964)), resolved(WatchState.color(rgb: 0xFF3B30))
        ])
    }
}
