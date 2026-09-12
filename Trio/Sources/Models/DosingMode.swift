import Foundation

/// How much of a determination Trio is allowed to enact on the pump.
enum AutomationLevel {
    /// Nothing reaches the pump. Trio forecasts and recommends only.
    case off
    /// Only a suspend when glucose is genuinely low. No other adjustment, in either direction.
    case hypoSuspendOnly
    /// Reductions only. Trio may lower or zero basal but never deliver above the scheduled rate.
    case reductionsOnly
    /// Unrestricted: reductions, corrections and SMBs.
    case full
}

/// How much of Trio's dosing decision is enacted, and under which constraints.
enum DosingMode: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case closed
    case open
    case lowGlucoseSuspend
    case basalTesting

    /// Only `closed` is automated insulin delivery in the full sense; the constrained modes
    /// can take insulin away but never add it, because Max IOB is clamped to 0.
    var automation: AutomationLevel {
        switch self {
        case .closed:
            return .full
        case .open:
            return .off
        case .lowGlucoseSuspend:
            return .reductionsOnly
        case .basalTesting:
            return .hypoSuspendOnly
        }
    }

    /// Modes offered in Settings.
    static var userSelectable: [DosingMode] { allCases }

    var displayName: String {
        switch self {
        case .closed:
            return String(localized: "Closed Loop", comment: "Dosing mode")
        case .open:
            return String(localized: "Open Loop", comment: "Dosing mode")
        case .lowGlucoseSuspend:
            return String(localized: "Low Glucose Suspend", comment: "Dosing mode")
        case .basalTesting:
            return String(localized: "Basal Testing", comment: "Dosing mode")
        }
    }

    var miniHint: String {
        switch self {
        case .closed:
            return String(localized: "Trio adjusts your insulin automatically.")
        case .open:
            return String(localized: "Trio only shows what it would do. It never changes your insulin.")
        case .lowGlucoseSuspend:
            return String(localized: "Trio may only lower basal insulin. It will not correct highs.")
        case .basalTesting:
            return String(localized: "Trio steps in only if your glucose goes low.")
        }
    }

    var explanation: String {
        switch self {
        case .closed:
            return String(
                localized: "Trio reviews your glucose about every five minutes and adjusts your insulin for you, using the settings you have entered. This requires an active CGM sensor session and a connected pump."
            )
        case .open:
            return String(
                localized: "Trio still calculates a forecast and a recommendation every few minutes, but it never sends anything to your pump. Your pump keeps delivering the basal rates you programmed, and every dose is your decision. Trio will not act to prevent a low or correct a high in this mode."
            )
        case .lowGlucoseSuspend:
            return String(
                localized: "Trio may reduce or stop your basal insulin when its forecast suggests you are heading low, but it will never give extra insulin to bring a high down. This is not a threshold-based suspend: Trio keeps adjusting basal from its forecast rather than cutting off at a set glucose value. While this mode is active your Maximum IOB is treated as 0 units. Your saved value is left untouched and returns when you change modes."
            )
        case .basalTesting:
            return String(
                localized: "For checking whether your basal rates hold you steady. Trio makes no adjustments at all unless your glucose actually goes low, in which case it stops your basal insulin until you recover. It never adds insulin back afterwards, and it stops adapting to changes in your sensitivity, so what you see is your profile behaving as you entered it. Meant for short, planned periods. Plan basal testing with your diabetes care team."
            )
        }
    }
}
