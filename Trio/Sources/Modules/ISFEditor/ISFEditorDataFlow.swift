//
// Trio
// ISFEditorDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-01-03.
// Most contributions by Ivan Valkou and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation

enum ISFEditor {
    enum Config {}

    class Item: Identifiable, Hashable, Equatable {
        let id = UUID()
        var rateIndex = 0
        var timeIndex = 0

        init(rateIndex: Int, timeIndex: Int) {
            self.rateIndex = rateIndex
            self.timeIndex = timeIndex
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.timeIndex == rhs.timeIndex && lhs.rateIndex == rhs.rateIndex
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(timeIndex)
            hasher.combine(rateIndex)
        }
    }
}

protocol ISFEditorProvider: Provider {
    var profile: InsulinSensitivities { get }
    func saveProfile(_ profile: InsulinSensitivities)
}
