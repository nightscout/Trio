//
//  TrioDataBridge.swift
//  Trio
//
//  Created by Orka on 2026-03-28.
//  Copyright © 2026 Trio Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Converts Trio's data models to the format expected by Pebble watch app
/// Handles glucose, insulin, and pump data conversion
final class TrioDataBridge {
    
    // MARK: - Glucose Data
    
    /// Update glucose data from Trio's Glucose model
    func updateGlucose(value: Double, unit: String, trend: String?, date: Date?) {
        // This would typically update internal state that the API server reads
        // For now, we assume the API server reads from a shared data source
        // In a real implementation, this might update a shared data manager
        NotificationCenter.default.post(name: .pebbleGlucoseUpdated, 
                                      object: nil,
                                      userInfo: [
                                        "value": value,
                                        "unit": unit,
                                        "trend": trend ?? "",
                                        "date": date?.timeIntervalSince1970 ?? 0
                                      ])
    }
    
    /// Update insulin data
    func updateInsulin(iob: Double?, cob: Double?, reservoir: Double?, battery: Double?) {
        NotificationCenter.default.post(name: .pebbleInsulinUpdated, 
                                      object: nil,
                                      userInfo: [
                                        "iob": iob ?? 0,
                                        "cob": cob ?? 0,
                                        "reservoir": reservoir ?? 0,
                                        "battery": battery ?? 0
                                      ])
    }
    
    /// Update pump status
    func updatePump(battery: Double?) {
        NotificationCenter.default.post(name: .pebblePumpUpdated, 
                                      object: nil,
                                      userInfo: [
                                        "battery": battery ?? 0
                                      ])
    }
    
    /// Update loop status
    func updateLoopStatus(isClosedLoop: Bool, lastRun: Date?, recommendedBolus: Double?, predicted: [Double]?) {
        NotificationCenter.default.post(name: .pebbleLoopUpdated, 
                                      object: nil,
                                      userInfo: [
                                        "isClosedLoop": isClosedLoop,
                                        "lastRun": lastRun?.timeIntervalSince1970 ?? 0,
                                        "recommendedBolus": recommendedBolus ?? 0,
                                        "predicted": predicted ?? []
                                      ])
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pebbleGlucoseUpdated = Notification.Name("pebbleGlucoseUpdated")
    static let pebbleInsulinUpdated = Notification.Name("pebbleInsulinUpdated")
    static let pebblePumpUpdated = Notification.Name("pebblePumpUpdated")
    static let pebbleLoopUpdated = Notification.Name("pebbleLoopUpdated")
}

// MARK: - Data Conversion Helpers

extension TrioDataBridge {
    
    /// Convert Trio's Glucose model to the format expected by Pebble API
    /// Returns dictionary suitable for JSON serialization
    static func formatGlucoseData(_ glucose: Glucose) -> [String: Any] {
        let glucoseValue = glucose.sgv ?? glucose.glucose ?? 0
        let trendString = glucose.direction?.rawValue ?? "none"
        
        return [
            "glucose": glucoseValue,           // mg/dL as integer
            "trend": trendString,              // e.g., "singleUp", "flat"
            "date": glucose.date.timeIntervalSince1970,
            "isValid": glucose.sgv != nil || glucose.glucose != nil
        ]
    }
    
    /// Format insulin on board data
    static func formatInsulinOnBoard(_ iob: Double) -> [String: Any] {
        return [
            "iob": iob
        ]
    }
    
    /// Format carbs on board data
    static func formatCarbsOnBoard(_ cob: Double) -> [String: Any] {
        return [
            "cob": cob
        ]
    }
    
    /// Format pump status data
    func formatPumpStatus(battery: Double?, reservoir: Double?) -> [String: Any] {
        return [
            "battery": battery ?? 0,
            "reservoir": reservoir ?? 0
        ]
    }
    
    /// Format loop prediction data
    func formatLoopPredictions(_ predicted: [Double]?) -> [String: Any] {
        return [
            "predicted": predicted ?? []
        ]
    }
}

// MARK: - Unit Conversion Helpers

extension TrioDataBridge {
    /// Convert mmol/L to mg/dL if needed
    static func mmolLToMgdL(_ mmolL: Double) -> Double {
        return mmolL * 18.018
    }
    
    /// Convert mg/dL to mmol/L if needed  
    static func mgdLToMMolL(_ mgdL: Double) -> Double {
        return mgdL / 18.018
    }
    
    /// Map Trio's glucose trend to Pebble-compatible format
    static func mapGlucoseTrend(_ direction: String?) -> String {
        // Trio uses strings like "singleUp", "doubleUp", etc.
        // Pebble expects similar format
        return direction ?? "none"
    }
}
