// Trio
// CalibrationsDataFlow.swift
// Created by Pierre L on 2024-04-02.

enum Calibrations {
    enum Config {}

    struct Item: Hashable, Identifiable {
        let calibration: Calibration

        var id: String {
            calibration.id.uuidString
        }
    }
}

protocol CalibrationsProvider {}
