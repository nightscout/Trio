import CoreData
import Foundation
import Swinject

class TrioRemoteControl: Injectable {
    static let shared = TrioRemoteControl()

    @Injected() internal var tempTargetsStorage: TempTargetsStorage!
    @Injected() internal var carbsStorage: CarbsStorage!
    @Injected() internal var nightscoutManager: NightscoutManager!
    @Injected() internal var overrideStorage: OverrideStorage!
    @Injected() internal var settings: SettingsManager!

    private let timeWindow: TimeInterval = 600 // Defines how old messages that are accepted, 10 minutes

    internal let pumpHistoryFetchContext: NSManagedObjectContext
    internal let viewContext: NSManagedObjectContext

    private init() {
        pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        viewContext = CoreDataStack.shared.persistentContainer.viewContext
        injectServices(TrioApp.resolver)
    }

    func handleRemoteNotification(pushMessage: PushMessage) async throws {
        let isTrioRemoteControlEnabled = UserDefaults.standard.bool(forKey: "isTrioRemoteControlEnabled")
        guard isTrioRemoteControlEnabled else {
            await logError("Remote command received, but remote control is disabled in settings. Ignoring the command.")
            return
        }

        let currentTime = Date().timeIntervalSince1970
        let timeDifference = currentTime - pushMessage.timestamp

        if timeDifference > timeWindow {
            await logError(
                "Command rejected: the message is too old (sent \(Int(timeDifference)) seconds ago, which exceeds the allowed limit).",
                pushMessage: pushMessage
            )
            return
        } else if timeDifference < -timeWindow {
            await logError(
                "Command rejected: the message has an invalid future timestamp (timestamp is \(Int(-timeDifference)) seconds ahead of the current time).",
                pushMessage: pushMessage
            )
            return
        }

        debug(.remoteControl, "Command received with acceptable time difference: \(Int(timeDifference)) seconds.")

        let storedSecret = UserDefaults.standard.string(forKey: "trioRemoteControlSharedSecret") ?? ""
        guard !storedSecret.isEmpty else {
            await logError(
                "Command rejected: shared secret is missing in settings. Cannot authenticate the command.",
                pushMessage: pushMessage
            )
            return
        }

        guard pushMessage.sharedSecret == storedSecret else {
            await logError(
                "Command rejected: shared secret does not match. Cannot authenticate the command.",
                pushMessage: pushMessage
            )
            return
        }

        switch pushMessage.commandType {
        case .bolus:
            try await handleBolusCommand(pushMessage)
        case .tempTarget:
            try await handleTempTargetCommand(pushMessage)
        case .cancelTempTarget:
            await cancelTempTarget(pushMessage)
        case .meal:
            try await handleMealCommand(pushMessage)

            if pushMessage.bolusAmount != nil {
                try await handleBolusCommand(pushMessage)
            }
        case .startOverride:
            await handleStartOverrideCommand(pushMessage)
        case .cancelOverride:
            await handleCancelOverrideCommand(pushMessage)
        }
    }
}

// MARK: - CommandType Enum

extension TrioRemoteControl {
    enum CommandType: String, Codable {
        case bolus
        case tempTarget = "temp_target"
        case cancelTempTarget = "cancel_temp_target"
        case meal
        case startOverride = "start_override"
        case cancelOverride = "cancel_override"

        var description: String {
            switch self {
            case .bolus:
                return "Bolus"
            case .tempTarget:
                return "Temporary Target"
            case .cancelTempTarget:
                return "Cancel Temporary Target"
            case .meal:
                return "Meal"
            case .startOverride:
                return "Start Override"
            case .cancelOverride:
                return "Cancel Override"
            }
        }
    }
}
