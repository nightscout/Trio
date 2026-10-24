import CoreData
import Foundation
import Swinject

/// Shared safety checks applied to any bolus command originating outside the main bolus UI
/// (remote notifications, Shortcuts, Apple Watch, etc.). Keeps validation logic consistent across call sites.
protocol BolusSafetyValidator {
    /// - Parameter lookbackStart: start of the window used for the recent-bolus 20% check.
    ///   Defaults to `now - BolusSafetyEvaluator.recentBolusWindowMinutes`. Callers that know when the
    ///   command was originally issued (e.g. APNS payload timestamp) should pass that instead so the
    ///   check covers any bolus since the command was sent.
    /// - Parameter overriding: checks the user has seen fail and chosen to bolus through. Only checks whose
    ///   `canBeOverridden` is true are skipped.
    func validate(
        bolusAmount: Decimal,
        lookbackStart: Date?,
        overriding: Set<BolusSafetyCheck>
    ) async throws -> BolusSafetyResult
    func fetchTotalRecentBolusAmount(since date: Date) async throws -> Decimal
}

extension BolusSafetyValidator {
    func validate(bolusAmount: Decimal) async throws -> BolusSafetyResult {
        try await validate(bolusAmount: bolusAmount, lookbackStart: nil, overriding: [])
    }

    func validate(bolusAmount: Decimal, lookbackStart: Date?) async throws -> BolusSafetyResult {
        try await validate(bolusAmount: bolusAmount, lookbackStart: lookbackStart, overriding: [])
    }
}

/// The individual checks `BolusSafetyEvaluator` runs. The raw values travel between the phone and the Watch.
enum BolusSafetyCheck: String, CaseIterable {
    case maxBolus = "max_bolus"
    case iobAvailable = "iob_available"
    case maxIOB = "max_iob"
    case recentBolus = "recent_bolus"

    /// Max bolus is a hard limit, as on the main bolus screen. The other checks only ask the user to confirm.
    var canBeOverridden: Bool {
        self != .maxBolus
    }

    /// How long a user's confirmation past a failed check stays valid. It matches the recent-bolus window, so the
    /// reason the user saw is at most about one loop cycle old.
    static let overrideLifetimeMinutes = BolusSafetyEvaluator.recentBolusWindowMinutes

    /// The checks a user confirmed to bolus through, or none if the confirmation has expired, so that every check
    /// runs again on current data.
    /// - Parameters:
    ///   - rawValues: The confirmed checks' raw values; unknown values are ignored
    ///   - issuedAt: When the user was asked to confirm, as seconds since 1970 on this device's clock
    static func overridden(_ rawValues: [String], issuedAt: TimeInterval?, now: Date = Date()) -> Set<BolusSafetyCheck> {
        guard let issuedAt,
              (0 ... TimeInterval(overrideLifetimeMinutes * 60)).contains(now.timeIntervalSince1970 - issuedAt)
        else { return [] }
        return Set(rawValues.compactMap(BolusSafetyCheck.init(rawValue:)))
    }
}

enum BolusSafetyResult: Equatable {
    case allowed
    case rejected(BolusSafetyRejection)
}

enum BolusSafetyRejection: Equatable {
    case exceedsMaxBolus(maxBolus: Decimal)
    case iobUnavailable
    case exceedsMaxIOB(currentIOB: Decimal, maxIOB: Decimal)
    case recentBolusWithinWindow(totalRecent: Decimal)

    var check: BolusSafetyCheck {
        switch self {
        case .exceedsMaxBolus: return .maxBolus
        case .iobUnavailable: return .iobAvailable
        case .exceedsMaxIOB: return .maxIOB
        case .recentBolusWithinWindow: return .recentBolus
        }
    }
}

extension BolusSafetyRejection {
    /// User-facing explanation of the rejection, shown by Shortcuts and on the Watch.
    func localizedMessage(requestedAmount: Decimal) -> String {
        switch self {
        case let .exceedsMaxBolus(maxBolus):
            return String(
                localized:
                "The bolus cannot be larger than the pump setting max bolus (\(maxBolus.description))."
            )
        case .iobUnavailable:
            return String(
                localized:
                "Bolus blocked: current IOB is not available."
            )
        case let .exceedsMaxIOB(currentIOB, maxIOB):
            return String(
                localized:
                "Bolus blocked: a \(requestedAmount.formatted()) U bolus would exceed max IOB (\(maxIOB.formatted()) U). Current IOB: \(currentIOB.formatted()) U."
            )
        case .recentBolusWithinWindow:
            return String(
                localized:
                "Bolus blocked: a significant bolus was delivered within the last \(BolusSafetyEvaluator.recentBolusWindowMinutes) minutes."
            )
        }
    }
}

struct BolusSafetyInputs: Equatable {
    let maxBolus: Decimal
    let maxIOB: Decimal
    let currentIOB: Decimal?
    /// Sum of bolus amounts delivered within the recent-bolus window (see `BolusSafetyEvaluator.recentBolusWindowMinutes`).
    let totalRecentBolus: Decimal
}

enum BolusSafetyEvaluator {
    static let recentBolusThreshold: Decimal = 0.2
    static let recentBolusWindowMinutes: Int = 6

    /// - Parameter overriding: checks to skip; those that cannot be overridden are run regardless.
    ///   With `.iobAvailable` overridden and no IOB, the max IOB check cannot run and is skipped too.
    static func evaluate(
        bolusAmount: Decimal,
        inputs: BolusSafetyInputs,
        overriding: Set<BolusSafetyCheck> = []
    ) -> BolusSafetyResult {
        let skipped = overriding.filter(\.canBeOverridden)
        if bolusAmount > inputs.maxBolus {
            return .rejected(.exceedsMaxBolus(maxBolus: inputs.maxBolus))
        }
        if let currentIOB = inputs.currentIOB {
            if !skipped.contains(.maxIOB), (currentIOB + bolusAmount) > inputs.maxIOB {
                return .rejected(.exceedsMaxIOB(currentIOB: currentIOB, maxIOB: inputs.maxIOB))
            }
        } else if !skipped.contains(.iobAvailable) {
            return .rejected(.iobUnavailable)
        }
        if !skipped.contains(.recentBolus), inputs.totalRecentBolus >= bolusAmount * recentBolusThreshold {
            return .rejected(.recentBolusWithinWindow(totalRecent: inputs.totalRecentBolus))
        }
        return .allowed
    }
}

final class BaseBolusSafetyValidator: BolusSafetyValidator, Injectable {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var iobService: IOBService!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func validate(
        bolusAmount: Decimal,
        lookbackStart: Date?,
        overriding: Set<BolusSafetyCheck>
    ) async throws -> BolusSafetyResult {
        let windowStart = lookbackStart
            ?? Date().addingTimeInterval(-Double(BolusSafetyEvaluator.recentBolusWindowMinutes * 60))
        let inputs = BolusSafetyInputs(
            maxBolus: settingsManager.pumpSettings.maxBolus,
            maxIOB: settingsManager.preferences.maxIOB,
            currentIOB: iobService.currentIOB,
            totalRecentBolus: try await fetchTotalRecentBolusAmount(since: windowStart)
        )
        return BolusSafetyEvaluator.evaluate(bolusAmount: bolusAmount, inputs: inputs, overriding: overriding)
    }

    func fetchTotalRecentBolusAmount(since date: Date) async throws -> Decimal {
        let fetchContext = CoreDataStack.shared.newTaskContext()
        fetchContext.name = "fetchTotalRecentBolusAmount"
        let predicate = NSPredicate(
            format: "type == %@ AND timestamp > %@",
            PumpEventStored.EventType.bolus.rawValue,
            date as NSDate
        )
        let results: Any = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: fetchContext,
            predicate: predicate,
            key: "timestamp",
            ascending: true,
            fetchLimit: nil,
            propertiesToFetch: ["bolus.amount"]
        )
        guard let bolusDictionaries = results as? [[String: Any]] else {
            throw CoreDataError.fetchError(function: #function, file: #file)
        }
        return bolusDictionaries.compactMap { ($0["bolus.amount"] as? NSNumber)?.decimalValue }.reduce(0, +)
    }
}
