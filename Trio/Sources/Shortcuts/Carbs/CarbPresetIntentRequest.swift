import CoreData
import Foundation

final class CarbPresetIntentRequest: BaseIntentsRequest {
    func addCarbs(
        _ quantityCarbs: Int,
        _ quantityFat: Int,
        _ quantityProtein: Int,
        _ dateAdded: Date,
        _ note: String?,
        _ dateDefinedByUser: Bool
    ) async throws -> String {
        guard quantityCarbs >= 0 || quantityFat >= 0 || quantityProtein >= 0 else {
            return "Amount must be positive."
        }

        try await carbsStorage.storeCarbs(
            [CarbsEntry(
                id: UUID().uuidString,
                createdAt: dateAdded,
                actualDate: dateAdded,
                carbs: Decimal(quantityCarbs),
                fat: Decimal(quantityFat),
                protein: Decimal(quantityProtein),
                note: (note?.isEmpty ?? true) ? "Via Shortcut" : note!,
                enteredBy: CarbsEntry.local,
                isFPU: false, fpuID: nil
            )],
            areFetchedFromRemote: false
        )
        var resultDisplay: String
        resultDisplay = String(localized: "Added \(quantityCarbs) g carbs")
        if quantityFat > 0 {
            resultDisplay = String(localized: "\(resultDisplay) and \(quantityFat) g fat")
        }
        if quantityProtein > 0 {
            resultDisplay = String(localized: "\(resultDisplay) and \(quantityProtein) g protein")
        }
        if dateDefinedByUser {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .none
            dateFormatter.timeStyle = .short

            let hourName = dateFormatter.string(from: dateAdded)
            resultDisplay = String(localized: "\(resultDisplay) at \(hourName)")

            let dayStatus = determineDateStatus(dateAdded)
            if let dayStatus = dayStatus {
                resultDisplay = String(localized: "\(resultDisplay)  \(dayStatus)")
            }
        }

        return resultDisplay
    }

    func determineDateStatus(_ date: Date) -> LocalizedStringResource? {
        let calendar = Calendar.current
        let now = Date()

        let dateStartOfDay = calendar.startOfDay(for: date)
        let nowStartOfDay = calendar.startOfDay(for: now)

        let components = calendar.dateComponents([.day], from: nowStartOfDay, to: dateStartOfDay)

        if let dayDifference = components.day {
            switch dayDifference {
            case -1:
                return LocalizedStringResource(stringLiteral: "Yesterday")
            case 0:
                return nil
            case 1:
                return LocalizedStringResource(stringLiteral: "Tomorrow")
            default:
                return nil
            }
        }
        return nil
    }
}
