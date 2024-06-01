import Foundation

/// A structure to descrive a Override as a exercise for NightScout
struct NightscoutExercise: JSON, Hashable, Equatable {
    var duration: Int?
    var eventType: EventType
    var createdAt: Date?
    var enteredBy: String?
    var notes: String?

    static let local = "Trio"

    static let empty = NightscoutExercise(from: "{}")!

    static func == (lhs: NightscoutExercise, rhs: NightscoutExercise) -> Bool {
        (lhs.createdAt ?? Date()) == (rhs.createdAt ?? Date())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt ?? Date())
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
