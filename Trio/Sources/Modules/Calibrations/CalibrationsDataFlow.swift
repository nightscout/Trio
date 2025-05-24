//
// Trio
// CalibrationsDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

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
