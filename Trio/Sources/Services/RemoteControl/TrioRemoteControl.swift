import CoreData
import Foundation
import Swinject

class TrioRemoteControl: Injectable {
    // Container-scoped singleton; shared is a convenience accessor for APNS/App Intents entry points
    static var shared: TrioRemoteControl { TrioApp.resolver.resolve(TrioRemoteControl.self)! }

    @Injected() internal var tempTargetsStorage: TempTargetsStorage!
    @Injected() internal var carbsStorage: CarbsStorage!
    @Injected() internal var nightscoutManager: NightscoutManager!
    @Injected() internal var adjustmentManager: AdjustmentManager!
    @Injected() internal var settings: SettingsManager!
    @Injected() internal var bolusSafetyValidator: BolusSafetyValidator!
    @Injected() internal var carbEntryMutationService: CarbEntryMutationService!
    @Injected() internal var apsManager: APSManager!
    @Injected() internal var therapyProfileManager: TherapyProfileManager!

    /// How long before now a command may have been sent.
    static let timeWindow: TimeInterval = 720
    /// How far ahead of now a command's send time may lie, for clock differences between the devices.
    static let futureTolerance: TimeInterval = 120

    private let commandQueue = RemoteCommandQueue()
    /// Core Data context the treatment guard reads boluses and carb entries from.
    var treatmentGuardStoreContext: () -> NSManagedObjectContext = { CoreDataStack.shared.newTaskContext() }
    /// Accessed only from `commandQueue`.
    @Persisted(key: "TrioRemoteControl.handledRemoteCommands") private var handledCommands = HandledRemoteCommands()

    private let pendingRemoteBolusLock = NSLock()
    private var pendingRemoteBolusValue: RemoteTreatmentGuard.InFlightBolus?
    /// The last remote bolus handed to the pump; counted by the treatment guard until it is in the dose history.
    var pendingRemoteBolus: RemoteTreatmentGuard.InFlightBolus? {
        get {
            pendingRemoteBolusLock.lock()
            defer { pendingRemoteBolusLock.unlock() }
            return pendingRemoteBolusValue
        }
        set {
            pendingRemoteBolusLock.lock()
            defer { pendingRemoteBolusLock.unlock() }
            pendingRemoteBolusValue = newValue
        }
    }

    /// Command ids of profile commands, kept for twice the accepted clock skew.
    let seenProfileCommands = RemoteCommandReplayGuard(window: 1200)

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    /// Clears the pending remote bolus if it is still `pending`.
    func clearPendingRemoteBolus(_ pending: RemoteTreatmentGuard.InFlightBolus) {
        pendingRemoteBolusLock.lock()
        defer { pendingRemoteBolusLock.unlock() }
        if pendingRemoteBolusValue == pending {
            pendingRemoteBolusValue = nil
        }
    }

    /// Records `payload` as handled and returns true, or returns false when the same command was already handled.
    /// A repeated command is logged to the app log only; the sender gets no reply and Nightscout no note.
    func markFirstHandling(of payload: CommandPayload, at date: Date) -> Bool {
        var handled = handledCommands
        let isFirst = handled.markHandled(payload, at: date)
        handledCommands = handled
        if !isFirst {
            warning(.remote, "Command already handled. Details: \(payload.humanReadableDescription())")
        }
        return isFirst
    }

    /// Rejection message for a command sent `timeDifference` seconds ago, or nil when it is within the window.
    static func timestampRejection(timeDifference: TimeInterval) -> String? {
        if timeDifference > timeWindow {
            return "Command rejected: the message is too old (sent \(Int(timeDifference)) seconds ago)."
        }
        if timeDifference < -futureTolerance {
            return "Command rejected: the message has an invalid future timestamp."
        }
        return nil
    }

    /// Handles one remote command at a time, in arrival order.
    func handleRemoteNotification(encryptedData: String) async throws {
        try await commandQueue.run {
            try await self.processRemoteNotification(encryptedData: encryptedData)
        }
    }

    private func processRemoteNotification(encryptedData: String) async throws {
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

        let messenger = SecureMessenger(sharedSecret: storedSecret)

        let commandPayload: CommandPayload
        do throws (SecureMessengerError) {
            commandPayload = try messenger.decrypt(base64EncodedString: encryptedData)
        } catch {
            let note = switch error {
            case .invalidMessage:
                "Command rejected: the message is not a valid remote command."
            case .authenticationFailed:
                "Command rejected: shared secret does not match. Enter the same shared secret in LoopFollow and in Trio's Remote Control settings."
            case .undecodableCommand:
                "Command rejected: the shared secret is correct, but this version of Trio cannot read the command. Check that Trio and LoopFollow are up to date."
            }
            await logError(note, logMessage: "\(note) Error: \(error)")
            return
        }

        // A repeat of a handled command is logged only, also when it arrives after the time window
        if !commandPayload.commandType.hasOwnReplayGuard, handledCommands.handledCommandId(of: commandPayload, at: Date()) {
            warning(.remote, "Command already handled. Details: \(commandPayload.humanReadableDescription())")
            return
        }

        let currentTime = Date().timeIntervalSince1970
        let timeDifference = currentTime - commandPayload.timestamp

        if let rejection = Self.timestampRejection(timeDifference: timeDifference) {
            await logError(
                rejection,
                payload: commandPayload,
                ack: RemoteCommandAck(commandId: commandPayload.commandId, mealId: commandPayload.mealId, result: .rejected)
            )
            return
        }

        debug(.remote, "Command authenticated, sent \(Int(timeDifference)) s ago")

        guard commandPayload.commandType.hasOwnReplayGuard || markFirstHandling(of: commandPayload, at: Date()) else { return }

        switch commandPayload.commandType {
        case .bolus:
            try await handleBolusCommand(commandPayload)
        case .tempTarget:
            try await handleTempTargetCommand(commandPayload)
        case .cancelTempTarget:
            await cancelTempTarget(commandPayload)
        case .meal:
            try await handleMealCommand(commandPayload)
        case .startOverride:
            await handleStartOverrideCommand(commandPayload)
        case .cancelOverride:
            await handleCancelOverrideCommand(commandPayload)
        case .deleteMeal:
            try await handleDeleteMealCommand(commandPayload)
        case .editMeal:
            try await handleEditMealCommand(commandPayload)
        case .switchProfile:
            await handleSwitchProfileCommand(commandPayload)
        case .saveProfile:
            await handleSaveProfileCommand(commandPayload)
        case .deleteProfile:
            await handleDeleteProfileCommand(commandPayload)
        case .saveScheduledSwitches:
            await handleSaveScheduledSwitchesCommand(commandPayload)
        case .unknown:
            await logError(
                "Command rejected: unsupported command type.",
                payload: commandPayload,
                ack: RemoteCommandAck(commandId: commandPayload.commandId, mealId: commandPayload.mealId, result: .rejected)
            )
        }
    }
}

/// Runs operations one after another; each starts once the previous one has finished.
actor RemoteCommandQueue {
    private var tail: Task<Void, Never>?

    func run(_ operation: @escaping () async throws -> Void) async throws {
        let previous = tail
        let task = Task {
            await previous?.value
            try await operation()
        }
        tail = Task { _ = await task.result }
        try await task.value
    }
}

/// Commands handled recently, so a repeated command is answered without being enacted again.
///
/// A command with a `commandId` is identified by it for `retention`. A command without one is identified by its
/// send time, type and values for as long as its send time passes the time window check.
struct HandledRemoteCommands: Codable, Equatable {
    static let retention: TimeInterval = 24 * 60 * 60
    static let contentRetention: TimeInterval = TrioRemoteControl.timeWindow + TrioRemoteControl.futureTolerance

    private(set) var expiresAt: [String: Date] = [:]

    /// Records `key` until `date + retention` and returns true, or returns false when it is still recorded.
    mutating func markHandled(_ key: String, at date: Date, retention: TimeInterval = Self.retention) -> Bool {
        expiresAt = expiresAt.filter { $0.value > date }
        guard expiresAt[key] == nil else { return false }
        expiresAt[key] = date.addingTimeInterval(retention)
        return true
    }

    /// Whether a command with the same `commandId` was handled and is still recorded at `date`.
    func handledCommandId(of payload: CommandPayload, at date: Date) -> Bool {
        guard let commandId = payload.commandId, let expiry = expiresAt["id:" + commandId] else { return false }
        return expiry > date
    }

    /// Records `payload` and returns true, or returns false when the same command was already handled.
    mutating func markHandled(_ payload: CommandPayload, at date: Date) -> Bool {
        if let commandId = payload.commandId {
            return markHandled("id:" + commandId, at: date)
        }
        return markHandled(Self.contentKey(of: payload), at: date, retention: Self.contentRetention)
    }

    /// Send time, command type and every value the command carries.
    static func contentKey(of payload: CommandPayload) -> String {
        let values: [String] = [
            payload.commandType.rawValue,
            "\(payload.timestamp)",
            payload.bolusAmount.map { "\($0)" } ?? "-",
            payload.carbs.map(String.init) ?? "-",
            payload.fat.map(String.init) ?? "-",
            payload.protein.map(String.init) ?? "-",
            payload.target.map(String.init) ?? "-",
            payload.duration.map(String.init) ?? "-",
            payload.overrideName ?? "-",
            payload.scheduledTime.map { "\($0)" } ?? "-",
            payload.mealId ?? "-"
        ]
        return "content:" + values.joined(separator: "|")
    }
}

extension TrioRemoteControl.CommandType {
    /// Profile commands reject a repeated `command_id` with a reply, through `seenProfileCommands`
    var hasOwnReplayGuard: Bool {
        switch self {
        case .deleteProfile,
             .saveProfile,
             .saveScheduledSwitches,
             .switchProfile:
            return true
        default:
            return false
        }
    }
}
