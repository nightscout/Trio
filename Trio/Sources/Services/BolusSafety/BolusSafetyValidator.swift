import CoreData
import Foundation
import Swinject

/// Shared safety checks applied to any bolus command originating outside the main bolus UI
/// (remote notifications, Shortcuts, etc.). Keeps validation logic consistent across call sites.
protocol BolusSafetyValidator {
    /// Max bolus, max IOB, and the recent-bolus 20% check over the last
    /// `BolusSafetyEvaluator.recentBolusWindowMinutes`.
    func validate(bolusAmount: Decimal) async throws -> BolusSafetyResult
    /// Max bolus and max IOB only, for callers that check recent treatments themselves.
    func validateLimits(bolusAmount: Decimal) -> BolusSafetyResult
    func fetchTotalRecentBolusAmount(since date: Date) async throws -> Decimal
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

    static func evaluateLimits(
        bolusAmount: Decimal,
        maxBolus: Decimal,
        maxIOB: Decimal,
        currentIOB: Decimal?
    ) -> BolusSafetyResult {
        if bolusAmount > maxBolus {
            return .rejected(.exceedsMaxBolus(maxBolus: maxBolus))
        }
        guard let currentIOB = currentIOB else {
            return .rejected(.iobUnavailable)
        }
        if (currentIOB + bolusAmount) > maxIOB {
            return .rejected(.exceedsMaxIOB(currentIOB: currentIOB, maxIOB: maxIOB))
        }
        return .allowed
    }

    static func evaluate(bolusAmount: Decimal, inputs: BolusSafetyInputs) -> BolusSafetyResult {
        let limits = evaluateLimits(
            bolusAmount: bolusAmount,
            maxBolus: inputs.maxBolus,
            maxIOB: inputs.maxIOB,
            currentIOB: inputs.currentIOB
        )
        guard limits == .allowed else { return limits }
        if inputs.totalRecentBolus >= bolusAmount * recentBolusThreshold {
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

    func validateLimits(bolusAmount: Decimal) -> BolusSafetyResult {
        BolusSafetyEvaluator.evaluateLimits(
            bolusAmount: bolusAmount,
            maxBolus: settingsManager.pumpSettings.maxBolus,
            maxIOB: settingsManager.preferences.maxIOB,
            currentIOB: iobService.currentIOB
        )
    }

    func validate(bolusAmount: Decimal) async throws -> BolusSafetyResult {
        let windowStart = Date().addingTimeInterval(-Double(BolusSafetyEvaluator.recentBolusWindowMinutes * 60))
        let inputs = BolusSafetyInputs(
            maxBolus: settingsManager.pumpSettings.maxBolus,
            maxIOB: settingsManager.preferences.maxIOB,
            currentIOB: iobService.currentIOB,
            totalRecentBolus: try await fetchTotalRecentBolusAmount(since: windowStart)
        )
        return BolusSafetyEvaluator.evaluate(bolusAmount: bolusAmount, inputs: inputs)
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
