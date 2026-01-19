//
//  GarminWatchState.swift
//  Trio
//
//  Created by Cengiz Deniz on 25.01.25.
//
import Foundation
import SwiftUI

// MARK: - Unified Garmin Watch State

/// Unified watch state structure for both Trio and SwissAlpine watchfaces.
/// Uses the SwissAlpine xDrip+ compatible data format.
/// Sent as an array where the first entry contains all extended data fields.
struct GarminWatchState: Hashable, Equatable, Sendable, Encodable {
    /// Timestamp of the glucose reading in milliseconds since Unix epoch
    var date: UInt64?
    var sgv: Int16?
    var delta: Int16?
    var direction: String?
    var noise: Double?
    var units_hint: String?
    var iob: Double?
    var tbr: Double?
    var cob: Double?
    var eventualBG: Int16?
    var isf: Int16?
    var sensRatio: Double?

    // MARK: - Display Configuration Fields

    /// Specifies which primary attribute to display
    /// Options: "cob", "isf", or "sensRatio"
    var displayPrimaryAttributeChoice: String?

    /// Specifies which secondary attribute to display
    /// Options: "tbr" or "eventualBG"
    var displaySecondaryAttributeChoice: String?

    static func == (lhs: GarminWatchState, rhs: GarminWatchState) -> Bool {
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
            lhs.sensRatio == rhs.sensRatio &&
            lhs.displayPrimaryAttributeChoice == rhs.displayPrimaryAttributeChoice &&
            lhs.displaySecondaryAttributeChoice == rhs.displaySecondaryAttributeChoice
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
        hasher.combine(displayPrimaryAttributeChoice)
        hasher.combine(displaySecondaryAttributeChoice)
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
        case displayPrimaryAttributeChoice
        case displaySecondaryAttributeChoice
    }

    /// Custom encoding that excludes nil values from the JSON output
    /// Double values are rounded to 2 decimal places to prevent floating point artifacts
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(sgv, forKey: .sgv)
        try container.encodeIfPresent(delta, forKey: .delta)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(noise, forKey: .noise)
        try container.encodeIfPresent(units_hint, forKey: .units_hint)
        // Round Double values to 2 decimal places to prevent floating point artifacts like "0.5600000000000001"
        try container.encodeIfPresent(iob?.roundedDouble(toPlaces: 2), forKey: .iob)
        try container.encodeIfPresent(tbr?.roundedDouble(toPlaces: 2), forKey: .tbr)
        try container.encodeIfPresent(cob, forKey: .cob)
        try container.encodeIfPresent(eventualBG, forKey: .eventualBG)
        try container.encodeIfPresent(isf, forKey: .isf)
        try container.encodeIfPresent(sensRatio?.roundedDouble(toPlaces: 2), forKey: .sensRatio)
        try container.encodeIfPresent(displayPrimaryAttributeChoice, forKey: .displayPrimaryAttributeChoice)
        try container.encodeIfPresent(displaySecondaryAttributeChoice, forKey: .displaySecondaryAttributeChoice)
    }
}
