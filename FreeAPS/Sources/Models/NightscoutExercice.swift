import Foundation

/// A structure to descrive a Override as a exercice for NightScout
struct NightscoutExercice: JSON, Hashable, Equatable {
    var duration: Int?
    var eventType: EventType
    var createdAt: Date?
    var enteredBy: String?
    var notes: String?

    static let local = "Trio"

    static let empty = NightscoutExercice(from: "{}")!

    static func == (lhs: NightscoutExercice, rhs: NightscoutExercice) -> Bool {
        (lhs.createdAt ?? Date()) == (rhs.createdAt ?? Date())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt ?? Date())
    }
}

extension NightscoutExercice {
    private enum CodingKeys: String, CodingKey {
        case duration
        case eventType
        case createdAt = "created_at"
        case enteredBy
        case notes
    }
}
