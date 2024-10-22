import CoreData
import Foundation
import Swinject

class TrioRemoteControl: Injectable {
    static let shared = TrioRemoteControl()

    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var nightscoutManager: NightscoutManager!
    @Injected() private var overrideStorage: OverrideStorage!

    private let timeWindow: TimeInterval = 600 // Defines how old messages that are accepted, 10 minutes

    private let pumpHistoryFetchContext: NSManagedObjectContext
    private let viewContext: NSManagedObjectContext

    private init() {
        pumpHistoryFetchContext = CoreDataStack.shared.newTaskContext()
        viewContext = CoreDataStack.shared.persistentContainer.viewContext
        injectServices(FreeAPSApp.resolver)
    }

    private func logError(_ errorMessage: String, pushMessage: PushMessage? = nil) async {
        var note = errorMessage
        if let pushMessage = pushMessage {
            note += " Details: \(pushMessage.humanReadableDescription())"
        }
        debug(.remoteControl, note)
        await nightscoutManager.uploadNoteTreatment(note: note)
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        let isTrioRemoteControlEnabled = UserDefaults.standard.bool(forKey: "isTrioRemoteControlEnabled")
        guard isTrioRemoteControlEnabled else {
            await logError("Remote command received, but remote control is disabled in settings. Ignoring the command.")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: userInfo)
            let pushMessage = try JSONDecoder().decode(PushMessage.self, from: jsonData)
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

            let storedSecret = UserDefaults.standard.string(forKey: "TRCsharedSecret") ?? ""
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
                await handleBolusCommand(pushMessage)
            case .tempTarget:
                await handleTempTargetCommand(pushMessage)
            case .cancelTempTarget:
                await cancelTempTarget()
            case .meal:
                await handleMealCommand(pushMessage)
            case .startOverride:
                await handleStartOverrideCommand(pushMessage)
            case .cancelOverride:
                await handleCancelOverrideCommand(pushMessage)
            }
        } catch {
            await logError("Error: unable to process the command due to decoding failure (\(error.localizedDescription)).")
        }
    }

    private func handleMealCommand(_ pushMessage: PushMessage) async {
        guard
            let carbs = pushMessage.carbs,
            let fat = pushMessage.fat,
            let protein = pushMessage.protein
        else {
            await logError("Command rejected: meal data is incomplete or invalid.", pushMessage: pushMessage)
            return
        }

        let settings = await FreeAPSApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settings?.maxCarbs ?? Decimal(0)
        let maxFat = settings?.maxFat ?? Decimal(0)
        let maxProtein = settings?.maxProtein ?? Decimal(0)

        if Decimal(carbs) > maxCarbs {
            await logError(
                "Command rejected: carbs amount (\(carbs)g) exceeds the maximum allowed (\(maxCarbs)g).",
                pushMessage: pushMessage
            )
            return
        }

        if Decimal(fat) > maxFat {
            await logError(
                "Command rejected: fat amount (\(fat)g) exceeds the maximum allowed (\(maxFat)g).",
                pushMessage: pushMessage
            )
            return
        }

        if Decimal(protein) > maxProtein {
            await logError(
                "Command rejected: protein amount (\(protein)g) exceeds the maximum allowed (\(maxProtein)g).",
                pushMessage: pushMessage
            )
            return
        }

        let pushMessageDate = Date(timeIntervalSince1970: pushMessage.timestamp)
        let recentCarbEntries = carbsStorage.recent()
        let carbsAfterPushMessage = recentCarbEntries.filter { $0.createdAt > pushMessageDate }

        if !carbsAfterPushMessage.isEmpty {
            await logError(
                "Command rejected: newer carb entries have been logged since the command was sent.",
                pushMessage: pushMessage
            )
            return
        }

        let actualDate: Date?
        if let scheduledTime = pushMessage.scheduledTime {
            actualDate = Date(timeIntervalSince1970: scheduledTime)
        } else {
            actualDate = nil
        }

        let mealEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: actualDate,
            carbs: Decimal(carbs),
            fat: Decimal(fat),
            protein: Decimal(protein),
            note: "Remote meal command",
            enteredBy: CarbsEntry.manual,
            isFPU: false,
            fpuID: nil
        )

        await carbsStorage.storeCarbs([mealEntry], areFetchedFromRemote: false)
        debug(.remoteControl, "Meal command processed successfully with carbs: \(carbs)g, fat: \(fat)g, protein: \(protein)g.")

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let dateString: String
        if let actualDate = actualDate {
            dateString = dateFormatter.string(from: actualDate)
        } else {
            dateString = dateFormatter.string(from: Date())
        }
        debug(
            .remoteControl,
            "Meal command processed successfully with carbs: \(carbs)g, fat: \(fat)g, protein: \(protein)g at \(dateString)."
        )
    }

    private func handleBolusCommand(_ pushMessage: PushMessage) async {
        guard let bolusAmount = pushMessage.bolusAmount else {
            await logError("Command rejected: bolus amount is missing or invalid.", pushMessage: pushMessage)
            return
        }

        let maxBolus = await FreeAPSApp.resolver.resolve(SettingsManager.self)?.pumpSettings.maxBolus ?? Decimal(0)

        if bolusAmount > maxBolus {
            await logError(
                "Command rejected: bolus amount (\(bolusAmount) units) exceeds the maximum allowed (\(maxBolus) units).",
                pushMessage: pushMessage
            )
            return
        }

        let totalRecentBolusAmount = await fetchTotalRecentBolusAmount(since: Date(timeIntervalSince1970: pushMessage.timestamp))

        if totalRecentBolusAmount >= bolusAmount * 0.2 {
            await logError(
                "Command rejected: boluses totaling more than 20% of the requested amount have been delivered since the command was sent.",
                pushMessage: pushMessage
            )
            return
        }

        debug(.remoteControl, "Enacting bolus command with amount: \(bolusAmount) units.")

        guard let apsManager = await FreeAPSApp.resolver.resolve(APSManager.self) else {
            await logError(
                "Error: unable to process bolus command because the APS Manager is not available.",
                pushMessage: pushMessage
            )
            return
        }

        await apsManager.enactBolus(amount: Double(truncating: bolusAmount as NSNumber), isSMB: false)
    }

    private func fetchTotalRecentBolusAmount(since date: Date) async -> Decimal {
        let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "type == %@ AND timestamp > %@",
            PumpEventStored.EventType.bolus.rawValue,
            date as NSDate
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        do {
            let totalAmount = try await pumpHistoryFetchContext.perform {
                let results = try self.pumpHistoryFetchContext.fetch(fetchRequest)
                var total = Decimal(0)
                for pumpEvent in results {
                    if let bolus = pumpEvent.bolus, let amount = bolus.amount?.decimalValue {
                        total += amount
                    }
                }
                return total
            }
            return totalAmount
        } catch {
            await logError("Failed to fetch recent bolus pump events: \(error.localizedDescription)")
            return Decimal(0)
        }
    }

    private func handleTempTargetCommand(_ pushMessage: PushMessage) async {
        guard let targetValue = pushMessage.target,
              let durationValue = pushMessage.duration
        else {
            await logError("Command rejected: temp target data is incomplete or invalid.", pushMessage: pushMessage)
            return
        }

        let durationInMinutes = Int(durationValue)
        let pushMessageDate = Date(timeIntervalSince1970: pushMessage.timestamp)

        let tempTarget = TempTarget(
            name: TempTarget.custom,
            createdAt: pushMessageDate,
            targetTop: Decimal(targetValue),
            targetBottom: Decimal(targetValue),
            duration: Decimal(durationInMinutes),
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom
        )

        tempTargetsStorage.storeTempTargets([tempTarget])
        debug(.remoteControl, "Temp target set with target: \(targetValue), duration: \(durationInMinutes) minutes.")
    }

    func cancelTempTarget() async {
        debug(.remoteControl, "Cancelling temp target.")

        guard tempTargetsStorage.current() != nil else {
            await logError("Command rejected: no active temp target to cancel.")
            return
        }

        let cancelEntry = TempTarget.cancel(at: Date())
        tempTargetsStorage.storeTempTargets([cancelEntry])
        debug(.remoteControl, "Temp target cancelled successfully.")
    }

    @MainActor private func handleCancelOverrideCommand(_: PushMessage) async {
        await disableAllActiveOverrides()
        debug(.remoteControl, "Active override cancelled successfully.")
    }

    @MainActor private func handleStartOverrideCommand(_ pushMessage: PushMessage) async {
        guard let overrideName = pushMessage.overrideName, !overrideName.isEmpty else {
            await logError("Command rejected: override name is missing.", pushMessage: pushMessage)
            return
        }

        let presetIDs = await overrideStorage.fetchForOverridePresets()

        let presets = presetIDs.compactMap { id in
            try? viewContext.existingObject(with: id) as? OverrideStored
        }

        if let preset = presets.first(where: { $0.name == overrideName }) {
            await enactOverridePreset(preset: preset)
            debug(.remoteControl, "Override '\(overrideName)' started successfully.")
        } else {
            await logError("Command rejected: override preset '\(overrideName)' not found.", pushMessage: pushMessage)
        }
    }

    @MainActor private func enactOverridePreset(preset: OverrideStored) async {
        await disableAllActiveOverrides()

        preset.enabled = true
        preset.date = Date()
        preset.isUploadedToNS = false

        do {
            if viewContext.hasChanges {
                try viewContext.save()

                Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                await awaitNotification(.didUpdateOverrideConfiguration)
            }
        } catch {
            debug(.remoteControl, "Failed to enact override preset: \(error.localizedDescription)")
        }
    }

    @MainActor func disableAllActiveOverrides() async {
        let ids = await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 0) // 0 = no fetch limit

        let didPostNotification = await viewContext.perform { () -> Bool in
            do {
                let results = try ids.compactMap { id in
                    try self.viewContext.existingObject(with: id) as? OverrideStored
                }

                guard !results.isEmpty else { return false }

                for canceledOverride in results where canceledOverride.enabled {
                    let newOverrideRunStored = OverrideRunStored(context: self.viewContext)
                    newOverrideRunStored.id = UUID()
                    newOverrideRunStored.name = canceledOverride.name
                    newOverrideRunStored.startDate = canceledOverride.date ?? .distantPast
                    newOverrideRunStored.endDate = Date()
                    newOverrideRunStored
                        .target = NSDecimalNumber(decimal: self.overrideStorage.calculateTarget(override: canceledOverride))
                    newOverrideRunStored.override = canceledOverride
                    newOverrideRunStored.isUploadedToNS = false

                    canceledOverride.enabled = false
                }

                if self.viewContext.hasChanges {
                    try self.viewContext.save()
                    Foundation.NotificationCenter.default.post(name: .willUpdateOverrideConfiguration, object: nil)
                    return true
                } else {
                    return false
                }
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to disable active Overrides with error: \(error.localizedDescription)"
                )
                return false
            }
        }

        if didPostNotification {
            await awaitNotification(.didUpdateOverrideConfiguration)
        }
    }

    func handleAPNSChanges(deviceToken: String?) async {
        let previousDeviceToken = UserDefaults.standard.string(forKey: "deviceToken")
        let previousIsAPNSProduction = UserDefaults.standard.bool(forKey: "isAPNSProduction")

        let isAPNSProduction = isRunningInAPNSProductionEnvironment()
        var shouldUploadProfiles = false

        if let token = deviceToken, token != previousDeviceToken {
            UserDefaults.standard.set(token, forKey: "deviceToken")
            debug(.remoteControl, "Device token updated: \(token)")
            shouldUploadProfiles = true
        }

        if previousIsAPNSProduction != isAPNSProduction {
            UserDefaults.standard.set(isAPNSProduction, forKey: "isAPNSProduction")
            debug(.remoteControl, "APNS environment changed to: \(isAPNSProduction ? "Production" : "Sandbox")")
            shouldUploadProfiles = true
        }

        if shouldUploadProfiles {
            await nightscoutManager.uploadProfiles()
        } else {
            debug(.remoteControl, "No changes detected in device token or APNS environment.")
        }
    }

    private func isRunningInAPNSProductionEnvironment() -> Bool {
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL {
            return appStoreReceiptURL.lastPathComponent != "sandboxReceipt"
        }
        return false
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
