import CoreData
import Foundation
import Swinject

// MARK: - Public surface

/// How a caller names the adjustment to activate.
enum AdjustmentRef: Equatable {
    case objectID(NSManagedObjectID)
    case presetID(String)
    case presetName(String)
}

enum AdjustmentSource: String {
    case app
    case remote
    case shortcut
    case watch
}

struct AdjustmentSummary: Equatable {
    let name: String?
    let startDate: Date
    let endDate: Date?
    /// Minutes, as stored on the adjustment.
    let duration: Decimal?
    let indefinite: Bool
}

struct AdjustmentOutcome: Equatable {
    let started: AdjustmentSummary?
    /// One entry per row that was enabled when the command arrived; each has a run entry.
    let ended: [AdjustmentSummary]
}

enum AdjustmentError: LocalizedError, Equatable {
    case presetNotFound(String)
    case nothingActive
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .presetNotFound(name):
            return String(localized: "Preset \"\(name)\" not found.", comment: "Adjustment preset not found")
        case .nothingActive:
            return String(localized: "Nothing is currently running.", comment: "No active adjustment to cancel")
        case .persistenceFailed:
            // The associated value carries the Core Data detail for the log, not for the reader.
            return String(localized: "Could not save the change.", comment: "Adjustment could not be saved")
        }
    }
}

/// Single writer for override and temp target activation.
///
/// Shortcuts, remote control and the watch route activation and cancellation through this
/// service, which performs the full sequence for each
/// command: end every enabled adjustment and record each one as a run entry, enable the requested
/// one, then apply the dependent side effects in a fixed order.
///
/// The run entry carries two jobs. It is the row the home chart renders as a finished adjustment
/// (`OverrideView`), and it is the row that carries the real duration to Nightscout, which
/// replaces the placeholder duration uploaded when the adjustment started
/// (`OverrideStorage.getOverrideRunsNotYetUploadedToNightscout`). Both `isUploadedToNS` flags are
/// cleared in the same transaction, which is what the Nightscout upload controllers key on
/// (`BaseNightscoutManager.wireUploadControllers`).
protocol AdjustmentManager {
    @discardableResult func activateOverride(
        _ preset: AdjustmentRef,
        source: AdjustmentSource,
        waitForUpload: Bool
    ) async throws -> AdjustmentOutcome

    @discardableResult func cancelOverride(source: AdjustmentSource, waitForUpload: Bool) async throws -> AdjustmentOutcome

    @discardableResult func activateTempTarget(
        _ preset: AdjustmentRef,
        source: AdjustmentSource,
        waitForUpload: Bool
    ) async throws -> AdjustmentOutcome

    @discardableResult func cancelTempTarget(source: AdjustmentSource, waitForUpload: Bool) async throws -> AdjustmentOutcome
}

extension AdjustmentManager {
    @discardableResult func activateOverride(
        _ preset: AdjustmentRef,
        source: AdjustmentSource
    ) async throws -> AdjustmentOutcome {
        try await activateOverride(preset, source: source, waitForUpload: false)
    }

    @discardableResult func cancelOverride(source: AdjustmentSource) async throws -> AdjustmentOutcome {
        try await cancelOverride(source: source, waitForUpload: false)
    }

    @discardableResult func activateTempTarget(
        _ preset: AdjustmentRef,
        source: AdjustmentSource
    ) async throws -> AdjustmentOutcome {
        try await activateTempTarget(preset, source: source, waitForUpload: false)
    }

    @discardableResult func cancelTempTarget(source: AdjustmentSource) async throws -> AdjustmentOutcome {
        try await cancelTempTarget(source: source, waitForUpload: false)
    }
}

// MARK: - Implementation

final class BaseAdjustmentManager: AdjustmentManager, Injectable, @unchecked Sendable {
    @Injected() private var tempTargetStorage: TempTargetsStorage!
    @Injected() private var nightscoutManager: NightscoutManager!
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!

    private let makeContext: () -> NSManagedObjectContext
    private let serializer = AdjustmentSerializer()
    /// Stands in for the determination step, so a caller can exercise the transaction on its own.
    private let recompute: (@Sendable() async -> Void)?

    init(
        resolver: Resolver,
        contextProvider: (() -> NSManagedObjectContext)? = nil,
        recompute: (@Sendable() async -> Void)? = nil
    ) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        self.recompute = recompute
        injectServices(resolver)
    }

    // MARK: Overrides

    @discardableResult func activateOverride(
        _ preset: AdjustmentRef,
        source: AdjustmentSource,
        waitForUpload: Bool
    ) async throws -> AdjustmentOutcome {
        let outcome = try await serializer.run { try await self.commitOverride(activating: preset) }
        debug(.service, "Override activated from \(source.rawValue): \(outcome.logDescription)")
        await applyOverrideSideEffects(source: source, waitForUpload: waitForUpload)
        return outcome
    }

    @discardableResult func cancelOverride(source: AdjustmentSource, waitForUpload: Bool) async throws -> AdjustmentOutcome {
        let outcome = try await serializer.run { try await self.commitOverride(activating: nil) }
        debug(.service, "Override cancelled from \(source.rawValue): \(outcome.logDescription)")
        await applyOverrideSideEffects(source: source, waitForUpload: waitForUpload)
        return outcome
    }

    /// `activating == nil` cancels whatever runs. Ending the active rows and enabling the
    /// requested one share one transaction, so no command can leave the app with nothing enabled
    /// or with two adjustments enabled at once.
    private func commitOverride(activating preset: AdjustmentRef?) async throws -> AdjustmentOutcome {
        let context = makeContext()
        context.name = "commitOverride"

        return try await context.perform {
            let now = Date()
            let target = try preset.map { try self.fetchOverride($0, in: context) }
            let active = try self.fetchActiveOverrides(in: context)

            if preset == nil, active.isEmpty {
                throw AdjustmentError.nothingActive
            }

            var ended: [AdjustmentSummary] = []
            // Every enabled row gets its own run entry. When the requested preset is the row that
            // is already running, the enable below restarts it and this entry holds the segment
            // that has elapsed.
            for row in active {
                let endDate = self.effectiveEndDate(start: row.date, duration: row.duration, indefinite: row.indefinite, now: now)
                let run = OverrideRunStored(context: context)
                run.id = UUID()
                run.name = row.name
                run.startDate = row.date ?? endDate
                run.endDate = endDate
                run.target = row.target ?? 0
                run.override = row
                run.isUploadedToNS = false

                row.enabled = false
                ended.append(AdjustmentSummary(row: row, startDate: run.startDate ?? endDate, endDate: endDate))
            }

            var started: AdjustmentSummary?
            if let target {
                target.enabled = true
                target.date = now
                target.isUploadedToNS = false
                started = AdjustmentSummary(row: target, startDate: now, endDate: nil)
            }

            try self.save(context)
            return AdjustmentOutcome(started: started, ended: ended)
        }
    }

    private func applyOverrideSideEffects(source: AdjustmentSource, waitForUpload: Bool) async {
        if waitForUpload {
            await nightscoutManager.uploadOverrides()
        } else {
            requestNightscoutUpload([.overrides], source: source.rawValue)
        }
        Foundation.NotificationCenter.default.post(name: .didUpdateOverrideConfiguration, object: nil)
        recomputeDetermination()
    }

    // MARK: Temp targets

    @discardableResult func activateTempTarget(
        _ preset: AdjustmentRef,
        source: AdjustmentSource,
        waitForUpload: Bool
    ) async throws -> AdjustmentOutcome {
        let (outcome, orefTarget) = try await serializer.run { try await self.commitTempTarget(activating: preset) }
        debug(.service, "Temp target activated from \(source.rawValue): \(outcome.logDescription)")
        await applyTempTargetSideEffects(orefTarget: orefTarget, source: source, waitForUpload: waitForUpload)
        return outcome
    }

    @discardableResult func cancelTempTarget(source: AdjustmentSource, waitForUpload: Bool) async throws -> AdjustmentOutcome {
        let (outcome, orefTarget) = try await serializer.run { try await self.commitTempTarget(activating: nil) }
        debug(.service, "Temp target cancelled from \(source.rawValue): \(outcome.logDescription)")
        await applyTempTargetSideEffects(orefTarget: orefTarget, source: source, waitForUpload: waitForUpload)
        return outcome
    }

    /// Returns the outcome plus the entry to hand oref, which has to be built inside the
    /// transaction while the row is still safe to read on this context.
    private func commitTempTarget(activating preset: AdjustmentRef?) async throws -> (AdjustmentOutcome, TempTarget?) {
        let context = makeContext()
        context.name = "commitTempTarget"

        return try await context.perform {
            let now = Date()
            let target = try preset.map { try self.fetchTempTarget($0, in: context) }
            let active = try self.fetchActiveTempTargets(in: context)

            if preset == nil, active.isEmpty {
                throw AdjustmentError.nothingActive
            }

            var ended: [AdjustmentSummary] = []
            for row in active {
                let endDate = self.effectiveEndDate(start: row.date, duration: row.duration, indefinite: false, now: now)
                let run = TempTargetRunStored(context: context)
                run.id = UUID()
                run.name = row.name
                run.startDate = row.date ?? endDate
                run.endDate = endDate
                run.target = row.target ?? 0
                run.tempTarget = row
                run.isUploadedToNS = false

                row.enabled = false
                ended.append(AdjustmentSummary(row: row, startDate: run.startDate ?? endDate, endDate: endDate))
            }

            var started: AdjustmentSummary?
            var orefTarget: TempTarget?
            if let target {
                target.enabled = true
                target.date = now
                target.isUploadedToNS = false
                started = AdjustmentSummary(row: target, startDate: now, endDate: nil)
                orefTarget = self.orefTempTarget(for: target, at: now)
            } else {
                // oref reads the newest entry in the temp targets file, so the entry that ends a
                // temp target carries the commit's own timestamp: file order then follows commit
                // order even when two commands land back to back.
                orefTarget = TempTarget.cancel(at: now)
            }

            try self.save(context)
            return (AdjustmentOutcome(started: started, ended: ended), orefTarget)
        }
    }

    private func applyTempTargetSideEffects(orefTarget: TempTarget?, source: AdjustmentSource, waitForUpload: Bool) async {
        if let orefTarget {
            // The write lands on the storage's own queue after this returns, so a determination
            // that starts immediately can still read the previous file contents.
            tempTargetStorage.saveTempTargetsToStorage([orefTarget])
        }
        if waitForUpload {
            await nightscoutManager.uploadTempTargets()
        } else {
            requestNightscoutUpload([.tempTargets], source: source.rawValue)
        }
        Foundation.NotificationCenter.default.post(name: .didUpdateTempTargetConfiguration, object: nil)
        recomputeDetermination()
    }

    /// The entry oref reads from the temp targets file. `halfBasalTarget` falls back to the
    /// preference, which is what the algorithm assumes when a preset carries none.
    private func orefTempTarget(for row: TempTargetStored, at date: Date) -> TempTarget {
        TempTarget(
            name: row.name,
            createdAt: date,
            targetTop: row.target?.decimalValue,
            targetBottom: row.target?.decimalValue,
            duration: row.duration?.decimalValue ?? 0,
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: row.isPreset,
            enabled: true,
            halfBasalTarget: row.halfBasalTarget?.decimalValue ?? settingsManager.preferences.halfBasalExerciseTarget
        )
    }

    // MARK: Shared

    /// Refreshes the determination and the forecast in the background: a command's outcome does not
    /// depend on it, so callers acknowledge as soon as the transaction has committed. The
    /// determination enacts nothing; delivery follows the loop.
    private func recomputeDetermination() {
        Task { [weak self] in
            guard let self else { return }
            if let recompute {
                await recompute()
                return
            }
            do {
                try await apsManager.determineBasalSync()
            } catch {
                debug(.service, "Determination after adjustment change failed: \(error)")
            }
        }
    }

    /// Runs end when they are cancelled, or when their duration ran out while they were still
    /// enabled, whichever came first.
    private func effectiveEndDate(start: Date?, duration: NSDecimalNumber?, indefinite: Bool, now: Date) -> Date {
        guard !indefinite,
              let start,
              let minutes = duration?.doubleValue,
              minutes > 0
        else { return now }
        let expiry = start.addingTimeInterval(minutes * 60)
        return min(now, expiry)
    }

    private func save(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            throw AdjustmentError.persistenceFailed(String(describing: error))
        }
    }

    private func fetchActiveOverrides(in context: NSManagedObjectContext) throws -> [OverrideStored] {
        let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
        request.predicate = NSPredicate.lastActiveOverride
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    private func fetchActiveTempTargets(in context: NSManagedObjectContext) throws -> [TempTargetStored] {
        let request: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
        request.predicate = NSPredicate.lastActiveTempTarget
        request.sortDescriptors = [NSSortDescriptor(key: "orderPosition", ascending: true)]
        return try context.fetch(request)
    }

    private func fetchOverride(_ ref: AdjustmentRef, in context: NSManagedObjectContext) throws -> OverrideStored {
        switch ref {
        case let .objectID(objectID):
            guard let row = try? context.existingObject(with: objectID) as? OverrideStored else {
                throw AdjustmentError.presetNotFound(objectID.uriRepresentation().lastPathComponent)
            }
            return row
        case let .presetID(id):
            let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else { throw AdjustmentError.presetNotFound(id) }
            return row
        case let .presetName(name):
            let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            request.predicate = NSPredicate(format: "isPreset == %@", true as NSNumber)
            request.sortDescriptors = [NSSortDescriptor(key: "orderPosition", ascending: true)]
            guard let row = try context.fetch(request).first(where: { $0.name?.matchesPresetName(name) == true }) else {
                throw AdjustmentError.presetNotFound(name)
            }
            return row
        }
    }

    private func fetchTempTarget(_ ref: AdjustmentRef, in context: NSManagedObjectContext) throws -> TempTargetStored {
        switch ref {
        case let .objectID(objectID):
            guard let row = try? context.existingObject(with: objectID) as? TempTargetStored else {
                throw AdjustmentError.presetNotFound(objectID.uriRepresentation().lastPathComponent)
            }
            return row
        case let .presetID(id):
            guard let uuid = UUID(uuidString: id) else { throw AdjustmentError.presetNotFound(id) }
            let request: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else { throw AdjustmentError.presetNotFound(id) }
            return row
        case let .presetName(name):
            let request: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            request.predicate = NSPredicate(format: "isPreset == %@", true as NSNumber)
            request.sortDescriptors = [NSSortDescriptor(key: "orderPosition", ascending: true)]
            guard let row = try context.fetch(request).first(where: { $0.name?.matchesPresetName(name) == true }) else {
                throw AdjustmentError.presetNotFound(name)
            }
            return row
        }
    }
}

// MARK: - Serialization

/// Runs adjustment mutations one at a time, in order: each starts after the previous one has
/// committed. Commands arrive from independent sources — a watch tap and a remote command can land
/// milliseconds apart — and each mutation reads the active rows, writes run entries and enables a
/// row, so it needs the previous one's committed state to be visible.
private actor AdjustmentSerializer {
    private var tail: Task<Void, Never>?

    /// Calling `run` from inside an operation deadlocks: the inner call waits for the outer one's
    /// place in the chain. An operation performs its own work and nothing else.
    func run<T: Sendable>(_ operation: @escaping @Sendable() async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

// MARK: - Helpers

private extension String {
    func matchesPresetName(_ name: String) -> Bool {
        trimmingCharacters(in: .whitespacesAndNewlines) == name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension AdjustmentSummary {
    init(row: OverrideStored, startDate: Date, endDate: Date?) {
        self.init(
            name: row.name,
            startDate: startDate,
            endDate: endDate,
            duration: row.duration?.decimalValue,
            indefinite: row.indefinite
        )
    }

    init(row: TempTargetStored, startDate: Date, endDate: Date?) {
        self.init(
            name: row.name,
            startDate: startDate,
            endDate: endDate,
            duration: row.duration?.decimalValue,
            indefinite: false
        )
    }
}

private extension AdjustmentOutcome {
    var logDescription: String {
        let startedText = started.map { "started \"\($0.name ?? "Custom")\"" } ?? "started nothing"
        let endedText = ended.isEmpty
            ? "ended nothing"
            : "ended \(ended.map { "\"\($0.name ?? "Custom")\"" }.joined(separator: ", "))"
        return "\(startedText), \(endedText)"
    }
}
