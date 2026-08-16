import Foundation
import HealthKit

extension TrioRemoteControl {
    func handleMealCommand(_ payload: CommandPayload) async throws {
        guard payload.carbs != nil || payload.fat != nil || payload.protein != nil else {
            await logError("Command rejected: meal data is incomplete or invalid.", payload: payload)
            return
        }

        let carbsDecimal = payload.carbs != nil ? Decimal(payload.carbs!) : nil
        let fatDecimal = payload.fat != nil ? Decimal(payload.fat!) : nil
        let proteinDecimal = payload.protein != nil ? Decimal(payload.protein!) : nil

        let settings = await TrioApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settings?.maxCarbs ?? Decimal(0)
        let maxFat = settings?.maxFat ?? Decimal(0)
        let maxProtein = settings?.maxProtein ?? Decimal(0)

        if let carbs = carbsDecimal, carbs > maxCarbs {
            await logError(
                "Command rejected: carbs amount (\(carbs)g) exceeds the maximum allowed (\(maxCarbs)g).",
                payload: payload
            )
            return
        }
        if let fat = fatDecimal, fat > maxFat {
            await logError("Command rejected: fat amount (\(fat)g) exceeds the maximum allowed (\(maxFat)g).", payload: payload)
            return
        }
        if let protein = proteinDecimal, protein > maxProtein {
            await logError(
                "Command rejected: protein amount (\(protein)g) exceeds the maximum allowed (\(maxProtein)g).",
                payload: payload
            )
            return
        }

        let payloadDate = Date(timeIntervalSince1970: payload.timestamp)
        let taskContext = CoreDataStack.shared.newTaskContext()
        // Only entries already in the past can indicate a replay; equivalents and scheduled
        // meals are dated ahead and would otherwise reject every command until their date passed.
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self, onContext: taskContext, predicate: NSPredicate(
                format: "date > %@ AND date <= %@",
                payloadDate as NSDate,
                Date() as NSDate
            ), key: "date", ascending: false
        )

        let hasNewerCarbEntries = await taskContext.perform {
            (results as? [CarbEntryStored])?.isEmpty == false
        }
        if hasNewerCarbEntries {
            await logError(
                "Command rejected: newer carb entries have been logged since the command was sent.",
                payload: payload
            )
            return
        }

        let actualDate = payload.scheduledTime.map { Date(timeIntervalSince1970: $0) }

        let mealEntry = CarbsEntry(
            id: UUID().uuidString, createdAt: Date(), actualDate: actualDate,
            carbs: carbsDecimal ?? 0, fat: fatDecimal, protein: proteinDecimal,
            note: "Remote meal command", enteredBy: CarbsEntry.local, isFPU: false,
            fpuID: fatDecimal ?? 0 > 0 || proteinDecimal ?? 0 > 0 ? UUID().uuidString : nil
        )

        try await carbsStorage.storeCarbs([mealEntry], areFetchedFromRemote: false)

        if payload.bolusAmount != nil {
            try await handleBolusCommand(payload)
            return
        }

        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: "Meal logged"
        )
    }
}

private struct RemoteMealMutationRequest {
    let expected: MealMutationValues
    let mutation: MealMutation
}

private struct RemoteMealMutationFingerprint: Encodable {
    let user: String
    let commandType: String
    let mealID: String
    let expectedCarbs: Int?
    let expectedFat: Int?
    let expectedProtein: Int?
    let expectedMealTime: TimeInterval?
    let carbs: Int?
    let fat: Int?
    let protein: Int?
    let scheduledTime: TimeInterval?
    let bolusAmount: Decimal?
    let target: Int?
    let duration: Int?
    let overrideName: String?
}

private struct RemoteMealMutationReceipt: Codable, Sendable {
    let commandID: String
    let fingerprint: String
    let mealID: String
    let success: Bool
    let message: String
    let result: MealMutationResponseResult
    let syncStatus: MealMutationSyncStatus
    let disposition: MealMutationDisposition?
    let before: MealMutationSnapshot?
    var cobRecalculated: Bool
    var serviceSyncAttemptFinished: Bool
    let isFinal: Bool
    let recordedAt: Date
}

private enum RemoteMealMutationReceiptClaim {
    case execute
    case resume(RemoteMealMutationReceipt)
    case replay(RemoteMealMutationReceipt)
    case conflict
    case inProgress
}

private actor RemoteMealMutationReceiptStore {
    static let shared = RemoteMealMutationReceiptStore()

    private struct ActiveMutation {
        let fingerprint: String
    }

    private let defaults = UserDefaults.standard
    private let key = "trio.remoteMealMutationReceipts.v1"
    private let maximumReceiptCount = 100
    private var activeCommands: [String: ActiveMutation] = [:]
    private var activeMeals: [String: String] = [:]

    func claim(
        commandID: String,
        mealID: String,
        fingerprint: String,
        now: Date
    ) -> RemoteMealMutationReceiptClaim {
        if let active = activeCommands[commandID] {
            return active.fingerprint == fingerprint ? .inProgress : .conflict
        }
        if activeMeals[mealID] != nil {
            return .inProgress
        }

        let receipts = loadReceipts(now: now)
        saveReceipts(receipts)
        if let receipt = receipts.first(where: { $0.commandID == commandID }) {
            guard receipt.fingerprint == fingerprint else {
                return .conflict
            }
            reserve(commandID: commandID, mealID: mealID, fingerprint: fingerprint)
            return receipt.isFinal ? .replay(receipt) : .resume(receipt)
        }

        reserve(commandID: commandID, mealID: mealID, fingerprint: fingerprint)
        return .execute
    }

    func record(_ receipt: RemoteMealMutationReceipt) {
        var receipts = loadReceipts(now: receipt.recordedAt)
        receipts.removeAll { $0.commandID == receipt.commandID }
        receipts.append(receipt)
        receipts.sort { $0.recordedAt < $1.recordedAt }
        if receipts.count > maximumReceiptCount {
            receipts = Array(receipts.suffix(maximumReceiptCount))
        }
        saveReceipts(receipts)
    }

    func release(commandID: String, mealID: String) {
        activeCommands.removeValue(forKey: commandID)
        if activeMeals[mealID] == commandID {
            activeMeals.removeValue(forKey: mealID)
        }
    }

    func remove(commandID: String) {
        var receipts = loadReceipts(now: Date())
        receipts.removeAll { $0.commandID == commandID }
        saveReceipts(receipts)
    }

    private func reserve(commandID: String, mealID: String, fingerprint: String) {
        activeCommands[commandID] = ActiveMutation(fingerprint: fingerprint)
        activeMeals[mealID] = commandID
    }

    private func loadReceipts(now: Date) -> [RemoteMealMutationReceipt] {
        guard let data = defaults.data(forKey: key),
              let receipts = try? JSONDecoder().decode([RemoteMealMutationReceipt].self, from: data)
        else {
            return []
        }

        return receipts.filter {
            let age = now.timeIntervalSince($0.recordedAt)
            return age >= 0 && age <= remoteMealMutationMaximumAge
        }
    }

    private func saveReceipts(_ receipts: [RemoteMealMutationReceipt]) {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        defaults.set(data, forKey: key)
    }
}

private enum RemoteMealMutationValidationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

extension TrioRemoteControl {
    func handleMealMutationCommand(_ payload: CommandPayload) async {
        let now = Date()

        guard let rawCommandID = payload.commandID,
              let commandID = UUID(uuidString: rawCommandID)?.uuidString
        else {
            await sendMealMutationResponse(
                payload: payload,
                success: false,
                message: "Command rejected: command_id must be a valid UUID.",
                result: .rejected,
                syncStatus: .notRequested
            )
            return
        }
        guard let rawMealID = payload.mealID,
              let mealID = UUID(uuidString: rawMealID)?.uuidString,
              let mealUUID = UUID(uuidString: mealID)
        else {
            await sendMealMutationResponse(
                payload: payload,
                success: false,
                message: "Command rejected: meal_id must be a valid Trio meal UUID.",
                result: .rejected,
                syncStatus: .notRequested,
                commandID: commandID
            )
            return
        }

        let fingerprint = Self.mealMutationFingerprint(payload: payload, mealID: mealID)
        let claim = await RemoteMealMutationReceiptStore.shared.claim(
            commandID: commandID,
            mealID: mealID,
            fingerprint: fingerprint,
            now: now
        )

        var resumedReceipt: RemoteMealMutationReceipt?
        switch claim {
        case let .replay(storedReceipt):
            var receipt = storedReceipt
            if receipt.success, !receipt.cobRecalculated, await recalculateCOB() {
                receipt.cobRecalculated = true
                await RemoteMealMutationReceiptStore.shared.record(receipt)
            }
            if receipt.success,
               let disposition = receipt.disposition,
               let before = receipt.before,
               disposition != .unchanged,
               !receipt.serviceSyncAttemptFinished
            {
                if await synchronizeMealMutation(disposition: disposition, before: before) {
                    receipt.serviceSyncAttemptFinished = true
                    await RemoteMealMutationReceiptStore.shared.record(receipt)
                }
            }
            await sendCompletedMealMutationResponse(receipt, payload: payload)
            await RemoteMealMutationReceiptStore.shared.release(commandID: commandID, mealID: mealID)
            return

        case let .resume(receipt):
            resumedReceipt = receipt

        case .conflict:
            await sendMealMutationResponse(
                payload: payload,
                success: false,
                message: "Command rejected: command_id was already used for a different request.",
                result: .rejected,
                syncStatus: .notRequested,
                commandID: commandID,
                mealID: mealID
            )
            return

        case .inProgress:
            await sendMealMutationResponse(
                payload: payload,
                success: false,
                message: "A command for this meal is already in progress. Retry shortly.",
                result: .inProgress,
                syncStatus: .notRequested,
                commandID: commandID,
                mealID: mealID
            )
            return

        case .execute:
            break
        }

        let request: RemoteMealMutationRequest
        do {
            request = try validatedMealMutationRequest(payload)
        } catch let error as RemoteMealMutationValidationError {
            await rejectClaimedMealMutation(
                error.localizedDescription,
                payload: payload,
                commandID: commandID,
                mealID: mealID,
                fingerprint: fingerprint,
                now: now
            )
            return
        } catch {
            await rejectClaimedMealMutation(
                "Command rejected: meal data is invalid.",
                payload: payload,
                commandID: commandID,
                mealID: mealID,
                fingerprint: fingerprint,
                now: now
            )
            return
        }

        let intendedDisposition: MealMutationDisposition = switch request.mutation {
        case .edit: .edited
        case .delete: .deleted
        }

        var preparedReceipt = resumedReceipt
        if preparedReceipt == nil {
            do {
                let before = try await carbsStorage.mealSnapshot(id: mealUUID, now: now)
                let pending = RemoteMealMutationReceipt(
                    commandID: commandID,
                    fingerprint: fingerprint,
                    mealID: mealID,
                    success: false,
                    message: "Meal change is prepared",
                    result: .inProgress,
                    syncStatus: .notRequested,
                    disposition: intendedDisposition,
                    before: before,
                    cobRecalculated: false,
                    serviceSyncAttemptFinished: false,
                    isFinal: false,
                    recordedAt: now
                )
                await RemoteMealMutationReceiptStore.shared.record(pending)
                preparedReceipt = pending
            } catch let error as MealMutationError {
                await rejectClaimedMealMutation(
                    "Command rejected: \(error.localizedDescription)",
                    payload: payload,
                    commandID: commandID,
                    mealID: mealID,
                    fingerprint: fingerprint,
                    now: now
                )
                return
            } catch {
                await RemoteMealMutationReceiptStore.shared.release(commandID: commandID, mealID: mealID)
                await sendMealMutationResponse(
                    payload: payload,
                    success: false,
                    message: "Meal change could not be prepared: \(error.localizedDescription)",
                    result: .rejected,
                    syncStatus: .notRequested,
                    commandID: commandID,
                    mealID: mealID
                )
                return
            }
        }

        guard let prepared = preparedReceipt, let preparedBefore = prepared.before else {
            await RemoteMealMutationReceiptStore.shared.remove(commandID: commandID)
            await RemoteMealMutationReceiptStore.shared.release(commandID: commandID, mealID: mealID)
            await sendMealMutationResponse(
                payload: payload,
                success: false,
                message: "Meal change could not be resumed because its receipt is incomplete.",
                result: .rejected,
                syncStatus: .notRequested,
                commandID: commandID,
                mealID: mealID
            )
            return
        }

        var mutationResult: MealMutationResult
        do {
            mutationResult = try await carbsStorage.mutateMeal(
                id: mealUUID,
                expected: request.expected,
                mutation: request.mutation,
                now: resumedReceipt?.recordedAt ?? now
            )
            if resumedReceipt != nil,
               intendedDisposition == .edited,
               mutationResult.disposition == .unchanged
            {
                mutationResult = MealMutationResult(
                    disposition: .edited,
                    before: preparedBefore,
                    after: mutationResult.after
                )
            }
        } catch let error as MealMutationError {
            if resumedReceipt != nil, intendedDisposition == .deleted, error == .notFound {
                mutationResult = MealMutationResult(disposition: .deleted, before: preparedBefore, after: nil)
            } else {
                await rejectClaimedMealMutation(
                    "Command rejected: \(error.localizedDescription)",
                    payload: payload,
                    commandID: commandID,
                    mealID: mealID,
                    fingerprint: fingerprint,
                    now: now
                )
                return
            }
        } catch {
            await RemoteMealMutationReceiptStore.shared.remove(commandID: commandID)
            await RemoteMealMutationReceiptStore.shared.release(commandID: commandID, mealID: mealID)
            await sendMealMutationResponse(
                payload: payload,
                success: false,
                message: "Meal change could not be saved: \(error.localizedDescription)",
                result: .rejected,
                syncStatus: .notRequested,
                commandID: commandID,
                mealID: mealID
            )
            return
        }

        let response: (message: String, result: MealMutationResponseResult, syncStatus: MealMutationSyncStatus)
        switch mutationResult.disposition {
        case .edited:
            response = ("Meal updated", .updated, .requested)
        case .deleted:
            response = ("Meal deleted", .deleted, .requested)
        case .unchanged:
            response = ("Meal change was already applied", .alreadyApplied, .notRequested)
        }

        var receipt = RemoteMealMutationReceipt(
            commandID: commandID,
            fingerprint: fingerprint,
            mealID: mealID,
            success: true,
            message: response.message,
            result: response.result,
            syncStatus: response.syncStatus,
            disposition: mutationResult.disposition,
            before: mutationResult.before,
            cobRecalculated: mutationResult.disposition == .unchanged,
            serviceSyncAttemptFinished: mutationResult.disposition == .unchanged,
            isFinal: true,
            recordedAt: now
        )
        await RemoteMealMutationReceiptStore.shared.record(receipt)

        if !receipt.cobRecalculated, await recalculateCOB() {
            receipt.cobRecalculated = true
            await RemoteMealMutationReceiptStore.shared.record(receipt)
        }

        if mutationResult.disposition != .unchanged {
            if await synchronizeMealMutation(
                disposition: mutationResult.disposition,
                before: mutationResult.before
            ) {
                receipt.serviceSyncAttemptFinished = true
                await RemoteMealMutationReceiptStore.shared.record(receipt)
            }
        }
        await sendCompletedMealMutationResponse(receipt, payload: payload)
        await RemoteMealMutationReceiptStore.shared.release(commandID: commandID, mealID: mealID)
    }

    private func validatedMealMutationRequest(_ payload: CommandPayload) throws -> RemoteMealMutationRequest {
        guard payload.commandType == .editMeal || payload.commandType == .deleteMeal else {
            throw RemoteMealMutationValidationError.message("Command rejected: unsupported meal operation.")
        }
        guard payload.bolusAmount == nil else {
            throw RemoteMealMutationValidationError.message(
                "Command rejected: meal edits and deletions cannot deliver a bolus."
            )
        }
        guard payload.target == nil, payload.duration == nil, payload.overrideName == nil else {
            throw RemoteMealMutationValidationError.message(
                "Command rejected: unrelated command fields were included."
            )
        }
        guard let expectedCarbs = payload.expectedCarbs,
              let expectedFat = payload.expectedFat,
              let expectedProtein = payload.expectedProtein,
              let expectedMealTime = payload.expectedMealTime,
              expectedMealTime.isFinite
        else {
            throw RemoteMealMutationValidationError.message(
                "Command rejected: all expected meal values and expected_meal_time are required."
            )
        }
        guard expectedCarbs >= 0, expectedFat >= 0, expectedProtein >= 0,
              expectedCarbs > 0 || expectedFat > 0 || expectedProtein > 0
        else {
            throw RemoteMealMutationValidationError.message(
                "Command rejected: expected meal amounts must be nonnegative and cannot all be zero."
            )
        }

        let expected = MealMutationValues(
            date: Date(timeIntervalSince1970: expectedMealTime),
            carbs: Decimal(expectedCarbs),
            fat: Decimal(expectedFat),
            protein: Decimal(expectedProtein)
        )

        switch payload.commandType {
        case .editMeal:
            guard let carbs = payload.carbs,
                  let fat = payload.fat,
                  let protein = payload.protein,
                  let scheduledTime = payload.scheduledTime,
                  scheduledTime.isFinite
            else {
                throw RemoteMealMutationValidationError.message(
                    "Command rejected: carbs, fat, protein, and scheduled_time are required for an edit."
                )
            }
            guard carbs >= 0, fat >= 0, protein >= 0, carbs > 0 || fat > 0 || protein > 0 else {
                throw RemoteMealMutationValidationError.message(
                    "Command rejected: replacement meal amounts must be nonnegative and cannot all be zero."
                )
            }

            let limits = settings.settings
            guard Decimal(carbs) <= limits.maxCarbs else {
                throw RemoteMealMutationValidationError.message(
                    "Command rejected: carbs amount (\(carbs)g) exceeds the maximum allowed (\(limits.maxCarbs)g)."
                )
            }
            guard Decimal(fat) <= limits.maxFat else {
                throw RemoteMealMutationValidationError.message(
                    "Command rejected: fat amount (\(fat)g) exceeds the maximum allowed (\(limits.maxFat)g)."
                )
            }
            guard Decimal(protein) <= limits.maxProtein else {
                throw RemoteMealMutationValidationError.message(
                    "Command rejected: protein amount (\(protein)g) exceeds the maximum allowed (\(limits.maxProtein)g)."
                )
            }

            return RemoteMealMutationRequest(
                expected: expected,
                mutation: .edit(MealMutationValues(
                    date: Date(timeIntervalSince1970: scheduledTime),
                    carbs: Decimal(carbs),
                    fat: Decimal(fat),
                    protein: Decimal(protein)
                ))
            )

        case .deleteMeal:
            guard payload.carbs == nil,
                  payload.fat == nil,
                  payload.protein == nil,
                  payload.scheduledTime == nil
            else {
                throw RemoteMealMutationValidationError.message(
                    "Command rejected: delete_meal cannot include replacement meal values."
                )
            }
            return RemoteMealMutationRequest(expected: expected, mutation: .delete)

        default:
            throw RemoteMealMutationValidationError.message("Command rejected: unsupported meal operation.")
        }
    }

    private func rejectClaimedMealMutation(
        _ message: String,
        payload: CommandPayload,
        commandID: String,
        mealID: String,
        fingerprint: String,
        now: Date
    ) async {
        let receipt = RemoteMealMutationReceipt(
            commandID: commandID,
            fingerprint: fingerprint,
            mealID: mealID,
            success: false,
            message: message,
            result: .rejected,
            syncStatus: .notRequested,
            disposition: nil,
            before: nil,
            cobRecalculated: true,
            serviceSyncAttemptFinished: true,
            isFinal: true,
            recordedAt: now
        )
        await RemoteMealMutationReceiptStore.shared.record(receipt)
        await RemoteMealMutationReceiptStore.shared.release(commandID: commandID, mealID: mealID)
        await sendMealMutationResponse(
            payload: payload,
            success: false,
            message: message,
            result: .rejected,
            syncStatus: .notRequested,
            commandID: commandID,
            mealID: mealID
        )
    }

    private func sendMealMutationResponse(
        payload: CommandPayload,
        success: Bool,
        message: String,
        result: MealMutationResponseResult,
        syncStatus: MealMutationSyncStatus,
        commandID: String? = nil,
        mealID: String? = nil
    ) async {
        let note = "\(message) Details: \(payload.humanReadableDescription())"
        if success {
            debug(.remoteControl, note)
        } else {
            debug(.remoteControl, note)
            await nightscoutManager.uploadNoteTreatment(note: note)
        }

        await RemoteNotificationResponseManager.shared.sendResponseNotification(
            to: payload.returnNotification,
            commandType: payload.commandType,
            success: success,
            message: message,
            commandID: commandID ?? payload.commandID,
            mealID: mealID ?? payload.mealID,
            result: result,
            syncStatus: syncStatus
        )
    }

    private func sendCompletedMealMutationResponse(
        _ receipt: RemoteMealMutationReceipt,
        payload: CommandPayload
    ) async {
        if receipt.success, !receipt.cobRecalculated || !receipt.serviceSyncAttemptFinished {
            await sendMealMutationResponse(
                payload: payload,
                success: false,
                message: "Meal change was saved locally, but follow-up processing is incomplete. Retry the same command.",
                result: .inProgress,
                syncStatus: receipt.serviceSyncAttemptFinished ? receipt.syncStatus : .notRequested,
                commandID: receipt.commandID,
                mealID: receipt.mealID
            )
            return
        }

        await sendMealMutationResponse(
            payload: payload,
            success: receipt.success,
            message: receipt.message,
            result: receipt.result,
            syncStatus: receipt.syncStatus,
            commandID: receipt.commandID,
            mealID: receipt.mealID
        )
    }

    private func synchronizeMealMutation(
        disposition: MealMutationDisposition,
        before: MealMutationSnapshot
    ) async -> Bool {
        guard disposition != .unchanged else { return true }

        if disposition == .edited, await tidepoolManager.waitForCarbUploads() == false { return false }

        await deleteMealSnapshotFromServices(before, deleteFromTidepool: disposition == .deleted)

        if disposition == .edited {
            do {
                try await carbsStorage.markMealForUpload(id: before.id)
            } catch {
                debug(.remoteControl, "Could not requeue the edited meal for upload: \(error.localizedDescription)")
                return false
            }

            async let nightscoutUpload: () = nightscoutManager.uploadCarbs()
            async let healthKitUpload: () = healthKitManager.uploadCarbs()
            async let tidepoolUpload: () = tidepoolManager.uploadCarbs()
            _ = await [nightscoutUpload, healthKitUpload, tidepoolUpload]
        }

        return true
    }

    private func recalculateCOB() async -> Bool {
        do {
            try await apsManager.determineBasalSync()
            return true
        } catch {
            debug(.remoteControl, "Meal change was saved, but COB recalculation failed: \(error.localizedDescription)")
            return false
        }
    }

    private func deleteMealSnapshotFromServices(
        _ snapshot: MealMutationSnapshot,
        deleteFromTidepool: Bool
    ) async {
        // Tidepool overwrites matching sync IDs on edit; only true deletions should enqueue a delete.
        if deleteFromTidepool {
            tidepoolManager.deleteCarbs(
                withSyncId: snapshot.id,
                carbs: snapshot.values.carbs,
                at: snapshot.values.date,
                enteredBy: CarbsEntry.local
            )
        }

        await nightscoutManager.deleteCarbs(withID: snapshot.id.uuidString)
        if let carbType = AppleHealthConfig.healthCarbObject {
            await healthKitManager.deleteMealData(byID: snapshot.id.uuidString, sampleType: carbType)
        }

        if let fpuID = snapshot.fpuID {
            await nightscoutManager.deleteCarbs(withID: fpuID.uuidString)
            if let fatType = AppleHealthConfig.healthFatObject {
                await healthKitManager.deleteMealData(byID: fpuID.uuidString, sampleType: fatType)
            }
            if let proteinType = AppleHealthConfig.healthProteinObject {
                await healthKitManager.deleteMealData(byID: fpuID.uuidString, sampleType: proteinType)
            }
        }
    }

    private static func mealMutationFingerprint(payload: CommandPayload, mealID: String) -> String {
        let value = RemoteMealMutationFingerprint(
            user: payload.user,
            commandType: payload.commandType.rawValue,
            mealID: mealID,
            expectedCarbs: payload.expectedCarbs,
            expectedFat: payload.expectedFat,
            expectedProtein: payload.expectedProtein,
            expectedMealTime: payload.expectedMealTime,
            carbs: payload.carbs,
            fat: payload.fat,
            protein: payload.protein,
            scheduledTime: payload.scheduledTime,
            bolusAmount: payload.bolusAmount,
            target: payload.target,
            duration: payload.duration,
            overrideName: payload.overrideName
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value).base64EncodedString()) ?? "invalid-fingerprint"
    }
}
