import Foundation

public struct CarbsEntry: JSON, Equatable, Hashable, Identifiable {
    public let id: String?
    public let createdAt: Date
    public let actualDate: Date?
    public let carbs: Decimal
    public let fat: Decimal?
    public let protein: Decimal?
    public let note: String?
    public let enteredBy: String?
    public let isFPU: Bool?
    public let fpuID: String?

    public init(
        id: String? = nil,
        createdAt: Date,
        actualDate: Date? = nil,
        carbs: Decimal,
        fat: Decimal? = nil,
        protein: Decimal? = nil,
        note: String? = nil,
        enteredBy: String? = nil,
        isFPU: Bool? = nil,
        fpuID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actualDate = actualDate
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.note = note
        self.enteredBy = enteredBy
        self.isFPU = isFPU
        self.fpuID = fpuID
    }

    static let local = "Trio"
    static let appleHealth = "applehealth"

    public static func == (lhs: CarbsEntry, rhs: CarbsEntry) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    public func hash(into hasher: inout Hasher) {
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
        case note = "notes"
        case enteredBy
        case isFPU
        case fpuID
    }
}
