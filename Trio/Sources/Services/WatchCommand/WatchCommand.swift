import Foundation

/// A state-changing command sent from a watch, already parsed and type-checked by its transport.
enum WatchCommand: Equatable {
    case bolus(Decimal)
    case carbs(Int)
    /// Carbs are stored before the bolus runs, so a rejected bolus still leaves the meal logged.
    case mealBolus(carbs: Int, bolus: Decimal)
    case activateOverride(name: String)
    case cancelOverride
    case activateTempTarget(name: String)
    case cancelTempTarget

    /// Wire name of the command; also the only command detail that is safe to log.
    var name: String {
        switch self {
        case .bolus: return "bolus"
        case .carbs: return "carbs"
        case .mealBolus: return "mealBolus"
        case .activateOverride: return "activateOverride"
        case .cancelOverride: return "cancelOverride"
        case .activateTempTarget: return "activateTempTarget"
        case .cancelTempTarget: return "cancelTempTarget"
        }
    }

    var bolusAmount: Decimal? {
        switch self {
        case let .bolus(units),
             let .mealBolus(_, units):
            return units
        default:
            return nil
        }
    }

    var carbsAmount: Int? {
        switch self {
        case let .carbs(grams),
             let .mealBolus(grams, _):
            return grams
        default:
            return nil
        }
    }
}

struct WatchCommandRequest: Equatable {
    let requestID: UUID
    /// Watch app that sent the command; request IDs are only unique per app.
    let appUUID: UUID
    /// When the watch issued the command.
    let date: Date
    let command: WatchCommand
}

extension WatchCommand {
    var isInsulin: Bool { bolusAmount != nil }

    /// Commands whose success changes which preset is active on the watch's preset list.
    var changesPresetState: Bool {
        switch self {
        case .activateOverride,
             .activateTempTarget,
             .cancelOverride,
             .cancelTempTarget:
            return true
        default:
            return false
        }
    }
}

/// Terminal answer to a watch command, sent back to the requesting app only.
struct WatchCommandResult: Equatable {
    let acknowledged: Bool
    let ackCode: BaseWatchManager.AcknowledgmentCode
    /// Short, user-facing text. Never carries amounts or internal error details.
    let message: String

    /// Something may have changed on the phone, so the watch needs fresh state.
    var refreshesState: Bool {
        acknowledged || ackCode == .partialFailure
    }

    static func success(_ ackCode: BaseWatchManager.AcknowledgmentCode, _ message: String) -> WatchCommandResult {
        WatchCommandResult(acknowledged: true, ackCode: ackCode, message: message)
    }

    static func failure(_ message: String) -> WatchCommandResult {
        WatchCommandResult(acknowledged: false, ackCode: .genericFailure, message: message)
    }
}

struct WatchCommandPresets: Equatable {
    let overridePresets: [OverridePresetWatch]
    let tempTargetPresets: [TempTargetPresetWatch]
}

/// An adjustment preset as the watch names it, plus the reference that activates exactly that row.
/// Every configured preset is listed and can be activated, whether it is running or not.
struct WatchPresetEntry: Equatable {
    let name: String
    /// Whether the preset is running right now (`enabled` on the stored row); it is sent to the
    /// watch as the v1 `isEnabled` key and never restricts activation.
    let isActive: Bool
    let ref: AdjustmentRef
}

/// Stable, content-free labels for command errors: Core Data and adjustment errors can carry
/// treatment values, preset names or store paths in their descriptions.
enum WatchCommandErrorCategory {
    static func name(for error: Error) -> String {
        switch error {
        case let adjustmentError as AdjustmentError:
            switch adjustmentError {
            case .presetNotFound: return "presetNotFound"
            case .nothingActive: return "nothingActive"
            case .persistenceFailed: return "adjustmentPersistence"
            }
        case is CoreDataError:
            return "coreData"
        case is CancellationError:
            return "cancelled"
        default:
            let nsError = error as NSError
            // a Cocoa code identifies Core Data failures without their user info
            return nsError.domain == NSCocoaErrorDomain ? "cocoa(\(nsError.code))" : "unexpected"
        }
    }
}
