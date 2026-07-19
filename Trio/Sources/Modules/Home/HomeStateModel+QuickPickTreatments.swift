import CoreData
import Foundation

/// A single historical amount (bolus units or carb grams) used to build Quick-Pick Treatment suggestions.
private struct QuickPickSample {
    let amount: Decimal
    let timestamp: Date
}

/// Scores samples by recency, time-of-day, and weekday/weekend similarity to "now", then returns the
/// rounded amounts with the highest scores. Shared by the bolus and carb Quick-Pick Treatment suggestion
/// loaders so the two amount types are ranked with identical logic.
private func topQuickPickSuggestions(
    from samples: [QuickPickSample],
    roundingScale: Int,
    limit: Int = 5
) -> [Decimal] {
    let now = Date()
    let cal = Calendar.current
    let nowMinute = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
    let nowDOW = cal.component(.weekday, from: now)
    let sigma: Double = 60.0
    let halfLife: Double = 10.0

    var groups: [Decimal: Double] = [:]
    for sample in samples {
        let roundedKey = sample.amount.rounded(scale: roundingScale)

        let entryMinute = cal.component(.hour, from: sample.timestamp) * 60 + cal.component(.minute, from: sample.timestamp)
        let entryDOW = cal.component(.weekday, from: sample.timestamp)

        let diff = abs(entryMinute - nowMinute)
        let circularDiff = Double(min(diff, 1440 - diff))
        let t = exp(-(circularDiff * circularDiff) / (2.0 * sigma * sigma))

        let d: Double
        if entryDOW == nowDOW {
            d = 1.0
        } else {
            let nowWeekend = nowDOW == 1 || nowDOW == 7
            let entryWeekend = entryDOW == 1 || entryDOW == 7
            d = nowWeekend == entryWeekend ? 0.7 : 0.15
        }

        let daysAgo = now.timeIntervalSince(sample.timestamp) / 86400.0
        let r = pow(0.5, daysAgo / halfLife)

        groups[roundedKey, default: 0] += t * d * r
    }

    return groups
        .filter { $0.key > 0 && $0.value >= 0.1 }
        .sorted { $0.value > $1.value }
        .prefix(limit)
        .map(\.key)
}

/// Fetches entities of `type` from the last `lookbackDays` days matching a cutoff-built predicate, and
/// scores them into Quick-Pick suggestions. Shared by the bolus and carb suggestion loaders, which differ
/// only in the entity type, predicate shape, and how a `QuickPickSample` is extracted from each entity.
private func fetchQuickPickSuggestions<T: NSManagedObject>(
    ofType type: T.Type,
    lookbackDays: Int = 90,
    predicate: (Date) -> NSPredicate,
    sortKey: String,
    roundingScale: Int,
    extractSample: @escaping (T) -> QuickPickSample?
) async -> [Decimal] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
    let fetchContext = CoreDataStack.shared.newTaskContext()
    do {
        let results: Any = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: type,
            onContext: fetchContext,
            predicate: predicate(cutoff),
            key: sortKey,
            ascending: false,
            batchSize: 100
        )

        return await fetchContext.perform {
            guard let entities = results as? [T] else { return [] }
            let samples = entities.compactMap(extractSample)
            return topQuickPickSuggestions(from: samples, roundingScale: roundingScale)
        }
    } catch {
        debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch quick-pick suggestions for \(type): \(error)")
        return []
    }
}

extension Home.StateModel {
    func loadQuickPickTreatmentSuggestions() async {
        guard enableQuickPickTreatments else { return }

        async let boluses = loadQuickPickBolusSuggestions()
        async let carbs = loadQuickPickCarbSuggestions()
        let (bolusSuggestions, carbSuggestions) = await (boluses, carbs)

        await MainActor.run {
            quickPickBolusSuggestions = bolusSuggestions
            quickPickCarbSuggestions = carbSuggestions
        }
    }

    private func loadQuickPickBolusSuggestions() async -> [Decimal] {
        // Don't suggest an amount the user's current Max Bolus setting won't let them deliver in full.
        let maxBolusUnits = pumpInitialSettings.maxBolusUnits
        return await fetchQuickPickSuggestions(
            ofType: BolusStored.self,
            predicate: { cutoff in
                NSPredicate(
                    format: "isSMB == false AND isExternal == false AND pumpEvent.timestamp >= %@",
                    cutoff as NSDate
                )
            },
            sortKey: "pumpEvent.timestamp",
            roundingScale: 2
        ) { bolus in
            guard let nsAmount = bolus.amount, nsAmount.doubleValue > 0, nsAmount.doubleValue <= maxBolusUnits,
                  let timestamp = bolus.pumpEvent?.timestamp else { return nil }
            return QuickPickSample(amount: nsAmount as Decimal, timestamp: timestamp)
        }
    }

    private func loadQuickPickCarbSuggestions() async -> [Decimal] {
        // Don't suggest an amount the user's current Max Carbs setting won't let them log in full.
        // Filtering here (before ranking) rather than after keeps a lowered Max Carbs from crowding out
        // otherwise-valid suggestions with over-cap entries that would just get dropped afterward.
        let maxCarbs = Double(truncating: settingsManager.settings.maxCarbs as NSDecimalNumber)
        return await fetchQuickPickSuggestions(
            ofType: CarbEntryStored.self,
            predicate: { cutoff in
                NSPredicate(format: "isFPU == false AND carbs > 0 AND date >= %@", cutoff as NSDate)
            },
            sortKey: "date",
            roundingScale: 0
        ) { entry in
            guard entry.carbs <= maxCarbs, let timestamp = entry.date else { return nil }
            return QuickPickSample(amount: Decimal(entry.carbs), timestamp: timestamp)
        }
    }

    /// Stores a Quick-Pick carb amount (mirroring `Treatments.StateModel.saveMeal()`). Returns `nil` if
    /// no carbs were requested, `.failed` if the amount was invalid or storage threw, `.succeeded`
    /// otherwise.
    private func storeQuickPickCarbs(_ carbAmount: Decimal?) async -> Home.QuickPickTreatmentOutcome.ActionResult? {
        guard let carbAmount else { return nil }
        guard carbAmount > 0 else { return .failed }

        do {
            // Suggestions are already filtered against Max Carbs when the sheet loads; re-cap here
            // defensively in case the setting changed while the sheet was open, matching
            // Treatments.StateModel.saveMeal()'s silent-capping behavior.
            let cappedCarbs = min(carbAmount, settingsManager.settings.maxCarbs)
            let carbsToStore = [carbsStorage.makeCarbEntry(carbs: cappedCarbs, date: Date())]
            try await carbsStorage.storeCarbs(carbsToStore, areFetchedFromRemote: false)
            return .succeeded
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Quick-pick treatment failed to save carbs: \(error)")
            return .failed
        }
    }

    /// Authenticates and enacts a Quick-Pick bolus. Returns `nil` if no bolus was requested, `.failed`
    /// if the amount was invalid or authentication was declined/failed, `.succeeded` otherwise.
    private func enactQuickPickBolus(_ bolusAmount: Decimal?) async -> Home.QuickPickTreatmentOutcome.ActionResult? {
        guard let bolusAmount else { return nil }
        guard bolusAmount > 0 else { return .failed }

        let delivery = min(
            Double(truncating: bolusAmount as NSDecimalNumber),
            pumpInitialSettings.maxBolusUnits
        )
        do {
            guard try await unlockmanager.unlock() else { return .failed }
            await apsManager.enactBolus(amount: delivery, isSMB: false, callback: nil)
            return .succeeded
        } catch {
            debug(.bolusState, "Quick-pick treatment bolus authentication error: \(error)")
            return .failed
        }
    }

    /// Enacts a Quick-Pick Treatment. Carbs are stored and the bolus is authenticated/enacted
    /// concurrently, since neither depends on the other's outcome, so a carb-only or bolus-only pick
    /// works the same as selecting both. Each half reports its own success/failure so the caller can
    /// tell the user about a partial failure instead of silently losing one half of a combined pick.
    func enactQuickPickTreatment(bolusAmount: Decimal?, carbAmount: Decimal?) async -> Home.QuickPickTreatmentOutcome {
        async let carbsResult = storeQuickPickCarbs(carbAmount)
        async let bolusResult = enactQuickPickBolus(bolusAmount)
        var outcome = Home.QuickPickTreatmentOutcome()
        (outcome.carbsResult, outcome.bolusResult) = await (carbsResult, bolusResult)

        // A successful bolus already triggers its own determine-basal sync; sync here whenever carbs
        // were saved and the bolus (if any) wasn't successfully enacted, matching
        // Treatments.StateModel.saveMeal().
        if outcome.carbsResult == .succeeded, outcome.bolusResult != .succeeded {
            do {
                try await apsManager.determineBasalSync()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Quick-pick treatment determine basal sync failed: \(error)")
            }
        }

        return outcome
    }
}
