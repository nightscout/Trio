import SwiftUI

enum NavigationDestinations: String {
    case acknowledgmentPending = "AcknowledgmentPendingView"
    case carbsInput = "CarbsInputView"
    case bolusInput = "BolusInputView"
    case bolusConfirm = "BolusConfirmView"
}

enum MealBolusStep: String {
    case savingCarbs = "Saving Carbs..."
    case enactingBolus = "Enacting Bolus..."
}

enum AcknowledgementStatus: String, CaseIterable {
    case success
    case failure
    case pending
}
