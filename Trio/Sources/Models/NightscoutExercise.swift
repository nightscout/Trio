//
// Trio
// NightscoutExercise.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct NightscoutExercise: JSON, Hashable, Equatable {
    var duration: Int?
    var eventType: OverrideStored.EventType
    var createdAt: Date
    var enteredBy: String?
    var notes: String?
    var id: UUID?

    static let local = "Trio"

    static func == (lhs: NightscoutExercise, rhs: NightscoutExercise) -> Bool {
        (lhs.createdAt) == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }
}

extension NightscoutExercise {
    private enum CodingKeys: String, CodingKey {
        case duration
        case eventType
        case createdAt = "created_at"
        case enteredBy
        case notes
    }
}
