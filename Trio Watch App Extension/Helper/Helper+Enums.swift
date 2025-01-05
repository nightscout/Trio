import SwiftUI

enum NavigationDestinations: String {
    case acknowledgmentPending
    case carbInput
    case bolusInput
    case bolusConfirm
}

enum MealBolusStep: String {
    case savingCarbs = "Saving Carbs..."
    case enactingBolus = "Enacting Bolus..."
    case completed = ""
}

enum AcknowledgementStatus: String, CaseIterable {
    case success
    case failure
    case pending
}
