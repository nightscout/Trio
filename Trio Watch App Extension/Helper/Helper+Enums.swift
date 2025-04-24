import SwiftUI
import WatchKit

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

enum AcknowledgmentCode: String, Codable {
    case savingCarbs = "saving_carbs"
    case enactingBolus = "enacting_bolus"
    case comboComplete = "combo_complete"
    case carbsLogged = "carbs_logged"
    case overrideStarted = "override_started"
    case overrideStopped = "override_stopped"
    case tempTargetStarted = "temp_target_started"
    case tempTargetStopped = "temp_target_stopped"
    case genericSuccess = "success"
    case genericFailure = "failure"
}

enum WatchSize {
    case watch40mm
    case watch41mm
    case watch42mm
    case watch44mm
    case watch45mm
    case watch49mm
    case unknown

    static var current: WatchSize {
        let bounds = WKInterfaceDevice.current().screenBounds

        switch bounds {
        case CGRect(x: 0, y: 0, width: 162, height: 197):
            return .watch40mm // check

        case CGRect(x: 0, y: 0, width: 176, height: 215):
            return .watch41mm // check

        case CGRect(x: 0, y: 0, width: 187, height: 223):
            return .watch42mm // check

        case CGRect(x: 0, y: 0, width: 184, height: 224):
            return .watch44mm

        case CGRect(x: 0, y: 0, width: 198, height: 242):
            return .watch45mm

        case CGRect(x: 0, y: 0, width: 205, height: 251):
            return .watch49mm
        default:
            return .unknown
        }
    }
}
