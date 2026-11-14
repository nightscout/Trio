import Foundation

/// Remembers command ids for a while, so a replayed command is recognized.
final class RemoteCommandReplayGuard {
    private let window: TimeInterval
    private let lock = NSLock()
    private var seen: [String: Date] = [:]

    init(window: TimeInterval) {
        self.window = window
    }

    /// Records `id` and returns true, or returns false when `id` was recorded within the window.
    func register(_ id: String, at now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        seen = seen.filter { now.timeIntervalSince($0.value) < window }
        guard seen[id] == nil else { return false }
        seen[id] = now
        return true
    }
}

extension TrioRemoteControl {
    static func profileAckResult(for error: Error) -> RemoteCommandAck.Result {
        switch error as? TherapyProfileError {
        case .conflict,
             .scheduledSwitchesConflict: return .conflict
        case .notFound: return .notFound
        default: return .rejected
        }
    }

    private func profileAck(_ payload: CommandPayload, _ result: RemoteCommandAck.Result) -> RemoteCommandAck {
        RemoteCommandAck(commandId: payload.commandId, mealId: nil, result: result)
    }

    private func requiredProfileName(_ payload: CommandPayload) -> String? {
        guard let name = payload.profileName, !name.isEmpty else { return nil }
        return name
    }

    /// The log names the command and its result; the profile name goes only to the sender and the Nightscout note.
    private func profileLogMessage(_ payload: CommandPayload, _ result: RemoteCommandAck.Result) -> String {
        "Remote command failed. \(payload.humanReadableDescription()) Result: \(result.rawValue)."
    }

    private func rejectProfileCommand(_ payload: CommandPayload, name: String, verb: String, reason: String) async {
        await logError(
            "Profile '\(name)' not \(verb): \(reason)",
            payload: payload,
            ack: profileAck(payload, .rejected),
            logMessage: profileLogMessage(payload, .rejected)
        )
    }

    /// Rejects a command whose `command_id` was already received. Commands without an id are not tracked.
    private func rejectReplayedProfileCommand(_ payload: CommandPayload, verb: String) async -> Bool {
        guard let commandId = payload.commandId, !commandId.isEmpty,
              !seenProfileCommands.register(commandId)
        else { return false }
        warning(.remote, "Profile command \(commandId) was already received")
        await rejectProfileCommand(
            payload,
            name: payload.profileName ?? "",
            verb: verb,
            reason: "This command was already received."
        )
        return true
    }

    private func failProfileCommand(_ payload: CommandPayload, name: String, verb: String, error: Error) async {
        let result = Self.profileAckResult(for: error)
        await logError(
            "Profile '\(name)' not \(verb): \(error.localizedDescription)",
            payload: payload,
            ack: profileAck(payload, result),
            logMessage: profileLogMessage(payload, result)
        )
    }

    func handleSwitchProfileCommand(_ payload: CommandPayload) async {
        guard await !rejectReplayedProfileCommand(payload, verb: "activated") else { return }
        guard let name = requiredProfileName(payload) else {
            await rejectProfileCommand(payload, name: "", verb: "activated", reason: "profile_name is missing.")
            return
        }
        guard let fingerprint = payload.baseFingerprint, !fingerprint.isEmpty else {
            await rejectProfileCommand(payload, name: name, verb: "activated", reason: "base_fingerprint is missing.")
            return
        }
        do {
            _ = try await therapyProfileManager.activate(name, expectedFingerprint: fingerprint, trigger: .remote)
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Profile '\(name)' activated",
                ack: profileAck(payload, .activated)
            )
        } catch {
            await failProfileCommand(payload, name: name, verb: "activated", error: error)
        }
    }

    func handleSaveProfileCommand(_ payload: CommandPayload) async {
        guard await !rejectReplayedProfileCommand(payload, verb: "saved") else { return }
        guard let name = requiredProfileName(payload) else {
            await rejectProfileCommand(payload, name: "", verb: "saved", reason: "profile_name is missing.")
            return
        }
        guard let compact = payload.profile else {
            await rejectProfileCommand(payload, name: name, verb: "saved", reason: "profile values are missing.")
            return
        }
        let originalName = payload.originalProfileName.flatMap { $0.isEmpty ? nil : $0 }
        if originalName != nil, payload.baseFingerprint?.isEmpty ?? true {
            await rejectProfileCommand(payload, name: name, verb: "saved", reason: "base_fingerprint is missing.")
            return
        }

        do {
            let original = originalName.flatMap { therapyProfileManager.profile(named: $0) }
            let profile = try compact.therapyProfile(named: name, original: original)
            let saved = try await therapyProfileManager.save(
                profile,
                originalName: originalName,
                baseFingerprint: payload.baseFingerprint
            )
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Profile '\(saved.isDefault ? name : saved.name)' saved",
                ack: profileAck(payload, .saved)
            )
        } catch {
            await failProfileCommand(payload, name: name, verb: "saved", error: error)
        }
    }

    func handleDeleteProfileCommand(_ payload: CommandPayload) async {
        guard await !rejectReplayedProfileCommand(payload, verb: "deleted") else { return }
        guard let name = requiredProfileName(payload) else {
            await rejectProfileCommand(payload, name: "", verb: "deleted", reason: "profile_name is missing.")
            return
        }
        guard let fingerprint = payload.baseFingerprint, !fingerprint.isEmpty else {
            await rejectProfileCommand(payload, name: name, verb: "deleted", reason: "base_fingerprint is missing.")
            return
        }
        do {
            let removedSwitches = try await therapyProfileManager.delete(name, expectedFingerprint: fingerprint)
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: removedSwitches == 0 ? "Profile '\(name)' deleted" :
                    "Profile '\(name)' deleted, \(removedSwitches) scheduled switches removed",
                ack: profileAck(payload, .deleted)
            )
        } catch {
            await failProfileCommand(payload, name: name, verb: "deleted", error: error)
        }
    }

    private func rejectScheduledSwitchesCommand(_ payload: CommandPayload, reason: String) async {
        await logError(
            "Scheduled switches not saved: \(reason)",
            payload: payload,
            ack: profileAck(payload, .rejected),
            logMessage: profileLogMessage(payload, .rejected)
        )
    }

    func handleSaveScheduledSwitchesCommand(_ payload: CommandPayload) async {
        if let commandId = payload.commandId, !commandId.isEmpty, !seenProfileCommands.register(commandId) {
            warning(.remote, "Profile command \(commandId) was already received")
            await rejectScheduledSwitchesCommand(payload, reason: "This command was already received.")
            return
        }
        guard let entries = payload.scheduledSwitches else {
            await rejectScheduledSwitchesCommand(payload, reason: "scheduled_switches is missing.")
            return
        }
        guard let fingerprint = payload.baseFingerprint, !fingerprint.isEmpty else {
            await rejectScheduledSwitchesCommand(payload, reason: "base_fingerprint is missing.")
            return
        }
        do {
            try await therapyProfileManager.saveScheduledSwitches(entries, baseFingerprint: fingerprint)
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "Scheduled switches saved",
                ack: profileAck(payload, .saved)
            )
        } catch {
            let result = Self.profileAckResult(for: error)
            await logError(
                "Scheduled switches not saved: \(error.localizedDescription)",
                payload: payload,
                ack: profileAck(payload, result),
                logMessage: profileLogMessage(payload, result)
            )
        }
    }
}
