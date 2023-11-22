import Foundation

struct CarbsEntry: JSON, Equatable, Hashable {
    let id: String?
    let createdAt: Date
    let actualDate: Date?
    let carbs: Decimal
    let fat: Decimal?
    let protein: Decimal?
    let note: String?
    let enteredBy: String?
    let isFPU: Bool?
    let fpuID: String?

    static let manual = "iAPS"
    static let appleHealth = "applehealth"

    static func == (lhs: CarbsEntry, rhs: CarbsEntry) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }
}

extension CarbsEntry {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt = "created_at"
        case actualDate
        case carbs
        case fat
        case protein
        case note
        case enteredBy
        case isFPU
        case fpuID
    }
}
