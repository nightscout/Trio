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
    @Injected() internal var iobService: IOBService!

    private let timeWindow: TimeInterval = 600

    internal let pumpHistoryFetchContext: NSManagedObjectContext
    internal let viewContext: NSManagedObjectContext

    private init() {
        pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        viewContext = CoreDataStack.shared.persistentContainer.viewContext
        injectServices(TrioApp.resolver)
    }

    func handleRemoteNotification(encryptedData: String) async throws {
        let isTrioRemoteControlEnabled = UserDefaults.standard.bool(forKey: "isTrioRemoteControlEnabled")
        guard isTrioRemoteControlEnabled else {
            await logError("Remote command received, but remote control is disabled in settings. Ignoring the command.")
            return
        }

        let storedSecret = UserDefaults.standard.string(forKey: "trioRemoteControlSharedSecret") ?? ""
        guard !storedSecret.isEmpty else {
            await logError("Command rejected: shared secret is missing in settings. Cannot authenticate the command.")
            return
        }

        guard let messenger = SecureMessenger(sharedSecret: storedSecret) else {
            await logError("Command rejected: Failed to initialize security module. The shared secret might be invalid.")
            return
        }

        let commandPayload: CommandPayload
        do {
            commandPayload = try messenger.decrypt(base64EncodedString: encryptedData)
        } catch {
            await logError(
                "Command rejected: Decryption failed. Mismatched shared secret or corrupted message. Error: \(error.localizedDescription)"
            )
            return
        }

        let currentTime = Date().timeIntervalSince1970
        let timeDifference = currentTime - commandPayload.timestamp

        if timeDifference > timeWindow {
            await logError(
                "Command rejected: the message is too old (sent \(Int(timeDifference)) seconds ago).",
                payload: commandPayload
            )
            return
        } else if timeDifference < -timeWindow {
            await logError(
                "Command rejected: the message has an invalid future timestamp.",
                payload: commandPayload
            )
            return
        }

        debug(
            .remoteControl,
            "Command successfully decrypted and authenticated. Time difference: \(Int(timeDifference)) seconds."
        )

        switch commandPayload.commandType {
        case .bolus:
            try await handleBolusCommand(commandPayload)
        case .tempTarget:
            try await handleTempTargetCommand(commandPayload)
        case .cancelTempTarget:
            await cancelTempTarget(commandPayload)
        case .meal:
            try await handleMealCommand(commandPayload)
            if commandPayload.bolusAmount != nil {
                try await handleBolusCommand(commandPayload)
            }
        case .startOverride:
            await handleStartOverrideCommand(commandPayload)
        case .cancelOverride:
            await handleCancelOverrideCommand(commandPayload)
        }
    }
}
