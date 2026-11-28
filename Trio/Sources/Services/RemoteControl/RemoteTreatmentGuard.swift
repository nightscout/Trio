import Foundation

/// A Nightscout `_id`: 24 hex characters whose first 8 are the server insertion time in seconds.
struct NightscoutObjectId: Equatable, Comparable {
    let value: String
    let date: Date

    init?(_ string: String?) {
        guard let string = string, string.utf8.count == 24,
              string.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) }),
              let seconds = UInt32(string.prefix(8), radix: 16)
        else { return nil }
        value = string.lowercased()
        date = Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func < (lhs: NightscoutObjectId, rhs: NightscoutObjectId) -> Bool {
        lhs.value < rhs.value
    }
}

/// Decides whether a remote bolus or carb command was sent without knowledge of treatments recorded on this device.
///
/// A candidate treatment is unknown to the sender when it is dated after the command's send time (a carb entry also
/// not after now), or, when the command carries a valid marker and treatments are uploaded to Nightscout, when it was
/// created after `_id` recording started and has no known Nightscout `_id` or an `_id` greater than the marker.
enum RemoteTreatmentGuard {
    static let lookback: TimeInterval = 6 * 60 * 60
    static let unknownInsulinThreshold: Decimal = 0.2
    /// A marker whose server time lies further ahead of now than this is invalid.
    static let markerFutureTolerance: TimeInterval = 5 * 60
    /// A manual bolus starting this long before a remote bolus was accepted can still be that remote bolus.
    static let pendingBolusMatchTolerance: TimeInterval = 10
    /// An accepted remote bolus counts for at most this long, also when the dose history never shows it.
    static let pendingBolusRetention: TimeInterval = 15 * 60
    /// A stored bolus within this time of the pump's bolus in progress, with the same programmed units, is that bolus.
    static let inProgressMatchTolerance: TimeInterval = 10
    static let inProgressUnitsTolerance: Decimal = 0.025

    /// Same bolus: start dates within 10 s and programmed units within 0.025 U, both inclusive. The margins absorb
    /// binary floating point error in dates and in units converted from `Double`.
    static func isSameBolus(date: Date, units: Decimal, as otherDate: Date, units otherUnits: Decimal) -> Bool {
        abs(date.timeIntervalSince(otherDate)) <= inProgressMatchTolerance + 0.001
            && abs(units - otherUnits) <= inProgressUnitsTolerance + 0.000001
    }

    struct Context {
        let sendTime: Date
        let now: Date
        /// Newest Nightscout `_id` the sender had seen.
        let knownThrough: NightscoutObjectId?
        let isNightscoutUploadEnabled: Bool
        /// When `_id` recording started for the configured site; the marker rule covers only candidates created after it.
        let markerRuleStart: Date?

        init(
            sendTime: Date,
            now: Date,
            knownThroughId: String?,
            isNightscoutUploadEnabled: Bool,
            markerRuleStart: Date?
        ) {
            self.sendTime = sendTime
            self.now = now
            knownThrough = NightscoutObjectId(knownThroughId).flatMap {
                $0.date.timeIntervalSince(now) > RemoteTreatmentGuard.markerFutureTolerance ? nil : $0
            }
            self.isNightscoutUploadEnabled = isNightscoutUploadEnabled
            self.markerRuleStart = markerRuleStart
        }

        var lookbackStart: Date { now.addingTimeInterval(-RemoteTreatmentGuard.lookback) }
    }

    struct Candidate: Equatable {
        let date: Date
        /// Delivered units for a finalized bolus, programmed units while in progress; grams for a carb entry.
        let amount: Decimal
        let nightscoutId: String?
        /// When the treatment was recorded on this device, or its date when no creation time is stored.
        let createdAt: Date

        init(date: Date, amount: Decimal, nightscoutId: String?, createdAt: Date? = nil) {
            self.date = date
            self.amount = amount
            self.nightscoutId = nightscoutId
            self.createdAt = createdAt ?? date
        }
    }

    struct StoredBolus: Equatable {
        let candidate: Candidate
        let syncIdentifier: String?
        let isAutomatic: Bool
        let programmedUnits: Decimal
    }

    /// A bolus being delivered or accepted for delivery that may not be in the dose history yet.
    struct InFlightBolus: Equatable {
        let date: Date
        /// Programmed units.
        let units: Decimal
        let syncIdentifier: String?
        let isAutomatic: Bool

        init(date: Date, units: Decimal, syncIdentifier: String?, isAutomatic: Bool = false) {
            self.date = date
            self.units = units
            self.syncIdentifier = syncIdentifier
            self.isAutomatic = isAutomatic
        }
    }

    enum Reason: Equatable {
        case afterSendTime
        case notUploaded
        case uploadedAfterMarker
    }

    enum Decision: Equatable {
        case allowed
        case unknownInsulin(units: Decimal, notUploadedOnly: Bool)
        case unknownCarbs(count: Int, grams: Decimal)
    }

    /// Insulin a bolus counts with: delivered units once finalized, at least the programmed units while in progress.
    static func bolusUnits(delivered: Decimal, programmed: Decimal, isInProgress: Bool) -> Decimal {
        isInProgress ? max(delivered, programmed) : delivered
    }

    /// Whether a bolus is the accepted remote bolus `pending`: not automatic, starting at or after 10 s before
    /// `pending` was accepted, with programmed units within 0.025 U of it (inclusive).
    static func isPendingBolus(
        _ pending: InFlightBolus,
        date: Date,
        programmedUnits: Decimal,
        isAutomatic: Bool
    ) -> Bool {
        !isAutomatic
            && date.timeIntervalSince(pending.date) >= -(pendingBolusMatchTolerance + 0.001)
            && abs(programmedUnits - pending.units) <= inProgressUnitsTolerance + 0.000001
    }

    /// The accepted remote bolus while it still counts: younger than `pendingBolusRetention` and not yet shown by
    /// the dose history or the pump's bolus in progress.
    static func activePendingBolus(
        _ pending: InFlightBolus?,
        stored: [StoredBolus],
        pumpBolusInProgress: InFlightBolus?,
        now: Date
    ) -> InFlightBolus? {
        guard let pending = pending, now.timeIntervalSince(pending.date) <= pendingBolusRetention else { return nil }
        let isRecorded = stored.contains {
            isPendingBolus(pending, date: $0.candidate.date, programmedUnits: $0.programmedUnits, isAutomatic: $0.isAutomatic)
        } || pumpBolusInProgress.map {
            isPendingBolus(pending, date: $0.date, programmedUnits: $0.units, isAutomatic: $0.isAutomatic)
        } ?? false
        return isRecorded ? nil : pending
    }

    /// Stored boluses plus the pump's bolus in progress and the active pending remote bolus, each unless the
    /// dose history already holds it.
    static func bolusCandidates(
        stored: [StoredBolus],
        pumpBolusInProgress: InFlightBolus?,
        pendingRemoteBolus: InFlightBolus?,
        now: Date
    ) -> [Candidate] {
        var candidates = stored.map(\.candidate)
        let storedSyncIdentifiers = Set(stored.compactMap(\.syncIdentifier))

        var inFlight: [InFlightBolus] = []
        if let pump = pumpBolusInProgress {
            let isStored = pump.syncIdentifier.map(storedSyncIdentifiers.contains) ?? false
                || stored.contains { storedBolus in
                    isSameBolus(
                        date: storedBolus.candidate.date,
                        units: storedBolus.programmedUnits,
                        as: pump.date,
                        units: pump.units
                    )
                }
            if !isStored {
                inFlight.append(pump)
            }
        }
        if let pending = activePendingBolus(
            pendingRemoteBolus,
            stored: stored,
            pumpBolusInProgress: pumpBolusInProgress,
            now: now
        ) {
            inFlight.append(pending)
        }

        candidates += inFlight.map { Candidate(date: $0.date, amount: $0.units, nightscoutId: nil) }
        return candidates
    }

    /// With `boundedByNow`, the send-time rule covers candidates dated up to now; without it, every candidate dated
    /// after the send time.
    static func unknownReason(_ candidate: Candidate, context: Context, boundedByNow: Bool = true) -> Reason? {
        if candidate.date > context.sendTime, !boundedByNow || candidate.date <= context.now {
            return .afterSendTime
        }
        guard let marker = context.knownThrough, context.isNightscoutUploadEnabled,
              let markerRuleStart = context.markerRuleStart, candidate.createdAt > markerRuleStart
        else {
            return nil
        }
        guard let objectId = NightscoutObjectId(candidate.nightscoutId) else {
            return .notUploaded
        }
        return objectId > marker ? .uploadedAfterMarker : nil
    }

    private static func unknownCandidates(
        _ candidates: [Candidate],
        context: Context,
        boundedByNow: Bool
    ) -> [(Candidate, Reason)] {
        candidates.compactMap { candidate in
            guard candidate.date >= context.lookbackStart,
                  let reason = unknownReason(candidate, context: context, boundedByNow: boundedByNow)
            else { return nil }
            return (candidate, reason)
        }
    }

    /// A bolus dated after the send time is unknown also when it is dated after now, as when the pump clock runs ahead.
    static func evaluateBolus(requested: Decimal, boluses: [Candidate], context: Context) -> Decision {
        let unknown = unknownCandidates(boluses, context: context, boundedByNow: false)
        let unknownUnits = unknown.reduce(Decimal(0)) { $0 + $1.0.amount }
        if unknownUnits > 0, unknownUnits >= requested * unknownInsulinThreshold {
            return .unknownInsulin(units: unknownUnits, notUploadedOnly: unknown.allSatisfy { $0.1 == .notUploaded })
        }
        return .allowed
    }

    /// A carb entry dated after now (a carb equivalent or scheduled meal) is judged by the marker rule only.
    static func evaluateCarbs(carbEntries: [Candidate], context: Context) -> Decision {
        let unknown = unknownCandidates(carbEntries, context: context, boundedByNow: true)
        guard !unknown.isEmpty else { return .allowed }
        return .unknownCarbs(count: unknown.count, grams: unknown.reduce(Decimal(0)) { $0 + $1.0.amount })
    }

    /// `value` rounded half up to `scale` decimals, printed with "." and without trailing zeros.
    static func format(_ value: Decimal, scale: Int) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        return NSDecimalNumber(decimal: rounded).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }
}

extension RemoteTreatmentGuard.Decision {
    var rejectionMessage: String? {
        switch self {
        case .allowed:
            return nil
        case let .unknownInsulin(units, notUploadedOnly):
            let insulin = RemoteTreatmentGuard.format(units, scale: 2)
            if notUploadedOnly {
                return "Command rejected: \(insulin) U of insulin has not been uploaded to Nightscout yet."
            }
            return "Command rejected: \(insulin) U of insulin was delivered after the command was sent (or after the newest treatment you had seen)."
        case let .unknownCarbs(count, grams):
            let carbs = RemoteTreatmentGuard.format(grams, scale: 0)
            if count == 1 {
                return "Command rejected: a carb entry of \(carbs) g was recorded that you had not seen."
            }
            return "Command rejected: \(count) carb entries totaling \(carbs) g were recorded that you had not seen."
        }
    }
}
