import Foundation
import SwiftUI

// MARK: - Trio Watchface Data Structure

/// Watch state structure for the Trio original watchface.
/// Uses string-based values for all fields to maintain compatibility with the original Trio watchface format.
struct GarminTrioWatchState: Hashable, Equatable, Sendable, Encodable {
    /// Current glucose value as a string (in user's selected units)
    var glucose: String?

    /// Glucose trend indicator (e.g., "↑", "↗", "→", "↘", "↓")
    var trendRaw: String?

    /// Change in glucose since last reading (e.g., "+5" or "-3")
    var delta: String?

    /// Insulin on board formatted as a string with one decimal place
    var iob: String?

    /// Carbs on board as a string
    var cob: String?

    /// Timestamp of the last loop run as Unix epoch time
    var lastLoopDateInterval: UInt64?

    /// Predicted eventual blood glucose value
    var eventualBGRaw: String?

    /// Current insulin sensitivity factor
    var isf: String?

    /// sensitivity ratio (included only if data type 1 is set to sensRatio)
    var sensRatio: String?

    static func == (lhs: GarminTrioWatchState, rhs: GarminTrioWatchState) -> Bool {
        lhs.glucose == rhs.glucose &&
            lhs.trendRaw == rhs.trendRaw &&
            lhs.delta == rhs.delta &&
            lhs.iob == rhs.iob &&
            lhs.cob == rhs.cob &&
            lhs.lastLoopDateInterval == rhs.lastLoopDateInterval &&
            lhs.eventualBGRaw == rhs.eventualBGRaw &&
            lhs.isf == rhs.isf &&
            lhs.sensRatio == rhs.sensRatio
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(glucose)
        hasher.combine(trendRaw)
        hasher.combine(delta)
        hasher.combine(iob)
        hasher.combine(cob)
        hasher.combine(lastLoopDateInterval)
        hasher.combine(eventualBGRaw)
        hasher.combine(isf)
        hasher.combine(sensRatio)
    }

    enum CodingKeys: String, CodingKey {
        case glucose
        case trendRaw
        case delta
        case iob
        case cob
        case lastLoopDateInterval
        case eventualBGRaw
        case isf
        case sensRatio
    }

    /// Custom encoding that excludes nil values from the JSON output
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(glucose, forKey: .glucose)
        try container.encodeIfPresent(trendRaw, forKey: .trendRaw)
        try container.encodeIfPresent(delta, forKey: .delta)
        try container.encodeIfPresent(iob, forKey: .iob)
        try container.encodeIfPresent(cob, forKey: .cob)
        try container.encodeIfPresent(lastLoopDateInterval, forKey: .lastLoopDateInterval)
        try container.encodeIfPresent(eventualBGRaw, forKey: .eventualBGRaw)
        try container.encodeIfPresent(isf, forKey: .isf)
        try container.encodeIfPresent(sensRatio, forKey: .sensRatio)
    }
}

// MARK: - SwissAlpine Watchface Data Structure

/// Watch state structure for the SwissAlpine xDrip+ compatible watchface.
/// Uses numeric types for efficiency and compatibility with xDrip+ data format.
/// An array of these structures is sent, with the first entry containing extended data fields.
struct GarminSwissAlpineWatchState: Hashable, Equatable, Sendable, Encodable {
    /// Timestamp of the glucose reading in milliseconds since Unix epoch
    var date: UInt64?

    /// Sensor glucose value in raw mg/dL (no unit conversion applied)
    var sgv: Int16?

    /// Change in glucose since previous reading as an integer
    var delta: Int16?

    /// Glucose trend direction (e.g., "Flat", "FortyFiveUp", "SingleUp")
    var direction: String?

    /// Signal noise level (optional, typically not used)
    var noise: Double?

    /// Unit hint for the watchface ("mgdl" or "mmol")
    var units_hint: String?

    /// Insulin on board as a decimal value (only in first array entry)
    var iob: Double?

    /// Current temp basal rate in U/hr (only in first array entry)
    var tbr: Double?

    /// Carbs on board as a decimal value (only in first array entry)
    var cob: Double?

    /// Predicted eventual blood glucose (excluded if data type 2 is set to TBR)
    var eventualBG: Int16?

    /// Current insulin sensitivity factor as an integer (only in first array entry)
    var isf: Int16?

    /// sensitivity ratio (included only if data type 1 is set to sensRatio)
    var sensRatio: Double?

    static func == (lhs: GarminSwissAlpineWatchState, rhs: GarminSwissAlpineWatchState) -> Bool {
        lhs.date == rhs.date &&
            lhs.sgv == rhs.sgv &&
            lhs.delta == rhs.delta &&
            lhs.direction == rhs.direction &&
            lhs.noise == rhs.noise &&
            lhs.units_hint == rhs.units_hint &&
            lhs.iob == rhs.iob &&
            lhs.tbr == rhs.tbr &&
            lhs.cob == rhs.cob &&
            lhs.eventualBG == rhs.eventualBG &&
            lhs.isf == rhs.isf &&
            lhs.sensRatio == rhs.sensRatio
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(sgv)
        hasher.combine(delta)
        hasher.combine(direction)
        hasher.combine(noise)
        hasher.combine(units_hint)
        hasher.combine(iob)
        hasher.combine(tbr)
        hasher.combine(cob)
        hasher.combine(eventualBG)
        hasher.combine(isf)
        hasher.combine(sensRatio)
    }

    enum CodingKeys: String, CodingKey {
        case date
        case sgv
        case delta
        case direction
        case noise
        case units_hint
        case iob
        case tbr
        case cob
        case eventualBG
        case isf
        case sensRatio
    }

    /// Custom encoding that excludes nil values from the JSON output
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(sgv, forKey: .sgv)
        try container.encodeIfPresent(delta, forKey: .delta)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(noise, forKey: .noise)
        try container.encodeIfPresent(units_hint, forKey: .units_hint)
        try container.encodeIfPresent(iob, forKey: .iob)
        try container.encodeIfPresent(tbr, forKey: .tbr)
        try container.encodeIfPresent(cob, forKey: .cob)
        try container.encodeIfPresent(eventualBG, forKey: .eventualBG)
        try container.encodeIfPresent(isf, forKey: .isf)
        try container.encodeIfPresent(sensRatio, forKey: .sensRatio)
    }
}
