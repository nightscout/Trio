import CoreData
import Foundation

/// Fills the chart's 72 h history with generated readings and treatments, so the rendering
/// paths that only show up under a full, busy history can be exercised on a fresh install.
///
/// Everything it writes is ordinary Core Data — the same entities the pump, CGM and carb
/// storages write — so the chart, the algorithm and every other reader see it exactly as they
/// see real data. That is the point of it, and also the reason it is dangerous: see
/// ``purge()``, and the warning the settings row carries.
///
/// **Seeded rows are marked.** Every record's `id` is a UUID whose first field is
/// ``signature``, derived from the record's own timestamp, so the set of rows this would write
/// is a pure function of the time window. Three things fall out of that:
///
/// - Running it twice cannot duplicate anything: a row whose id is already there is skipped.
/// - Running it again later fills only what is missing — the hours that have passed since,
///   and any gap left by a purge or by data that aged out.
/// - ``purge()`` can find every seeded row and nothing else, however long ago it was written.
enum MockChartDataSeeder {
    /// How far back a seed reaches: the chart's own history window.
    static let historySeconds = MainChartHelper.Config.chartHistorySeconds

    /// First field of every seeded record's UUID — `0xC0DEDA7A`, spelled in the hex digits a
    /// UUID allows. This is the mark: nothing else distinguishes a seeded row from a real one,
    /// and a purge deletes exactly the rows carrying it.
    static let signature = "C0DEDA7A"

    /// How far back a purge sweeps. Generous on purpose: rows seeded during an earlier session
    /// have since aged past the 72 h window, and leaving them behind would mean the toggle
    /// could not honestly claim to have removed what it wrote.
    private static let purgeLookback: TimeInterval = 30 * 24 * 3600

    /// What a run did, for the settings row to report.
    struct Summary: Equatable {
        var glucose = 0
        var boluses = 0
        var smbs = 0
        var carbs = 0
        var fpus = 0

        var total: Int { glucose + boluses + smbs + carbs + fpus }
    }

    // MARK: - Seeding

    /// Writes every planned record the store does not already have, and returns what it added.
    ///
    /// Idempotent in both directions: a second run right after the first adds nothing, and a
    /// run a day later adds only that day. Glucose additionally yields to whatever is already
    /// there — a 5-minute slot holding a real reading is left alone rather than doubled up, so
    /// this fills the gaps around live CGM data instead of fighting it.
    @discardableResult static func seed() async throws -> Summary {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "mockChartDataSeed"

        let end = Date.now
        let start = end.addingTimeInterval(-historySeconds)

        return try await context.perform {
            var summary = Summary()

            let occupiedSlots = try glucoseSlots(in: start ... end, on: context)
            let existingEventIDs = try mockPumpEventIDs(from: start, on: context)
            let existingCarbIDs = try mockCarbIDs(from: start, on: context)

            for reading in plannedGlucose(from: start, to: end) {
                guard !occupiedSlots.contains(slot(of: reading.date)) else { continue }
                insert(reading, into: context)
                summary.glucose += 1
            }

            for dose in plannedDoses(from: start, to: end) {
                guard !existingEventIDs.contains(dose.id.uuidString) else { continue }
                insert(dose, into: context)
                if dose.isSMB { summary.smbs += 1 } else { summary.boluses += 1 }
            }

            for entry in plannedCarbs(from: start, to: end) {
                guard !existingCarbIDs.contains(entry.id) else { continue }
                insert(entry, into: context)
                if entry.isFPU { summary.fpus += 1 } else { summary.carbs += 1 }
            }

            guard context.hasChanges else { return summary }
            try context.save()
            debug(.coreData, "\(DebuggingIdentifiers.succeeded) Seeded \(summary.total) mock chart records")
            return summary
        }
    }

    // MARK: - Removal

    /// Deletes every row carrying ``signature`` and returns how many went.
    ///
    /// Real data is never touched: the mark is on the row's own id, so this cannot remove a
    /// reading the CGM wrote or a bolus the pump delivered, whatever their timestamps.
    @discardableResult static func purge() async throws -> Int {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "mockChartDataPurge"
        let since = Date.now.addingTimeInterval(-purgeLookback)

        return try await context.perform {
            var deleted = 0

            let glucose = try context.fetch(glucoseRequest(from: since))
            for reading in glucose where isSeeded(reading.id) {
                context.delete(reading)
                deleted += 1
            }

            // `PumpEventStored.bolus` cascades, so the bolus row goes with its event.
            let events = try context.fetch(seededPumpEventRequest(from: since))
            for event in events {
                context.delete(event)
                deleted += 1
            }

            let carbs = try context.fetch(carbRequest(from: since))
            for entry in carbs where isSeeded(entry.id) {
                context.delete(entry)
                deleted += 1
            }

            guard context.hasChanges else { return deleted }
            try context.save()
            debug(.coreData, "\(DebuggingIdentifiers.succeeded) Purged \(deleted) mock chart records")
            return deleted
        }
    }

    /// How many seeded rows are currently in the store — what the settings row reads to know
    /// which way the switch should be sitting when the screen opens.
    static func seededRecordCount() async throws -> Int {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "mockChartDataCount"
        let since = Date.now.addingTimeInterval(-purgeLookback)

        return try await context.perform {
            let glucose = try context.fetch(glucoseRequest(from: since)).filter { isSeeded($0.id) }.count
            let events = try context.count(for: seededPumpEventRequest(from: since))
            let carbs = try context.fetch(carbRequest(from: since)).filter { isSeeded($0.id) }.count
            return glucose + events + carbs
        }
    }

    // MARK: - The mark

    /// Whether a record's id was minted by this seeder.
    static func isSeeded(_ id: UUID?) -> Bool {
        id?.uuidString.hasPrefix("\(signature)-") ?? false
    }

    /// Which series a seeded id belongs to. Only the first field marks a row as seeded; this
    /// second field is what keeps two series from minting the same id for the same instant.
    private enum Kind: UInt16 {
        case glucose = 1
        case bolus = 2
        case smb = 3
        case carb = 4
        case fpu = 5
    }

    /// The id a given record gets — a pure function of its series, its timestamp and, for the
    /// rare series that puts two rows in one second, its index. Determinism is what makes a
    /// re-run fill holes instead of duplicating.
    ///
    /// Force-unwrapped because it cannot fail: the format string always yields the 8-4-4-4-12
    /// hex layout `UUID(uuidString:)` parses, and `signature` is a hex literal.
    private static func id(_ kind: Kind, at date: Date, index: Int = 0) -> UUID {
        UUID(uuidString: String(
            format: "%@-%04X-0000-%04X-%012llX",
            signature,
            Int(kind.rawValue),
            Int(UInt16(truncatingIfNeeded: index)),
            UInt64(max(date.timeIntervalSince1970.rounded(), 0))
        ))!
    }

    // MARK: - Fetches

    private static func glucoseRequest(from date: Date) -> NSFetchRequest<GlucoseStored> {
        let request = GlucoseStored.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@", date as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: true)]
        return request
    }

    private static func carbRequest(from date: Date) -> NSFetchRequest<CarbEntryStored> {
        let request = CarbEntryStored.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@", date as NSDate)
        return request
    }

    /// Seeded pump events alone. `PumpEventStored.id` is a string attribute, so unlike the
    /// UUID-keyed entities this one can be narrowed to the mark in the store rather than in
    /// memory.
    private static func seededPumpEventRequest(from date: Date) -> NSFetchRequest<PumpEventStored> {
        let request = PumpEventStored.fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND id BEGINSWITH %@",
            date as NSDate,
            "\(signature)-"
        )
        return request
    }

    /// The 5-minute slots that already hold a reading — real or seeded.
    private static func glucoseSlots(
        in range: ClosedRange<Date>,
        on context: NSManagedObjectContext
    ) throws -> Set<Int> {
        let request: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            range.lowerBound as NSDate,
            range.upperBound as NSDate
        )
        return Set(try context.fetch(request).compactMap { $0.date.map(slot(of:)) })
    }

    private static func mockPumpEventIDs(from date: Date, on context: NSManagedObjectContext) throws -> Set<String> {
        Set(try context.fetch(seededPumpEventRequest(from: date)).compactMap(\.id))
    }

    private static func mockCarbIDs(from date: Date, on context: NSManagedObjectContext) throws -> Set<UUID> {
        Set(try context.fetch(carbRequest(from: date)).compactMap(\.id).filter { isSeeded($0) })
    }

    // MARK: - Insertion

    private static func insert(_ reading: PlannedGlucose, into context: NSManagedObjectContext) {
        let stored = GlucoseStored(context: context)
        stored.id = reading.id
        stored.date = reading.date
        stored.glucose = reading.value
        stored.direction = reading.direction.rawValue
        stored.isManual = false
        // Seeded data must never leave the device: it is not the user's, and an upload would
        // put it somewhere this switch cannot take it back from.
        stored.isUploadedToNS = true
        stored.isUploadedToHealth = true
        stored.isUploadedToTidepool = true
    }

    private static func insert(_ dose: PlannedDose, into context: NSManagedObjectContext) {
        let event = PumpEventStored(context: context)
        let identifier = dose.id.uuidString
        event.id = identifier
        event.syncIdentifier = identifier
        event.isMutable = false
        event.timestamp = dose.date
        event.type = PumpEventStored.EventType.bolus.rawValue
        event.note = noteMarker
        event.isUploadedToNS = true
        event.isUploadedToHealth = true
        event.isUploadedToTidepool = true

        let bolus = BolusStored(context: context)
        bolus.pumpEvent = event
        bolus.amount = dose.amount as NSDecimalNumber
        bolus.programmedAmount = dose.amount as NSDecimalNumber
        bolus.isExternal = false
        bolus.isSMB = dose.isSMB
    }

    private static func insert(_ entry: PlannedCarb, into context: NSManagedObjectContext) {
        let stored = CarbEntryStored(context: context)
        stored.id = entry.id
        stored.date = entry.date
        stored.carbs = entry.carbs
        stored.fat = entry.fat
        stored.protein = entry.protein
        stored.isFPU = entry.isFPU
        stored.fpuID = entry.fpuID
        stored.note = noteMarker
        stored.isUploadedToNS = true
        stored.isUploadedToHealth = true
        stored.isUploadedToTidepool = true
    }

    /// Carried on the entities that have a note field, so a seeded row is recognizable by eye
    /// in the history list too — not just by its id.
    private static let noteMarker = "Trio mock data"

    // MARK: - The plan

    private struct PlannedGlucose {
        let id: UUID
        let date: Date
        let value: Int16
        let direction: BloodGlucose.Direction
    }

    private struct PlannedDose {
        let id: UUID
        let date: Date
        let amount: Decimal
        let isSMB: Bool
    }

    private struct PlannedCarb {
        let id: UUID
        let date: Date
        let carbs: Double
        let fat: Double
        let protein: Double
        let isFPU: Bool
        let fpuID: UUID?
    }

    /// CGM cadence, and the grid everything glucose is quantized to.
    private static let readingInterval: TimeInterval = 300

    /// Which 5-minute slot of absolute time a date falls in. Anchored to the epoch rather than
    /// to "now", so the grid is the same on every run and a later seed lines its readings up
    /// with the ones already stored instead of interleaving a second, offset series.
    private static func slot(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / readingInterval).rounded(.down))
    }

    private static func date(ofSlot slot: Int) -> Date {
        Date(timeIntervalSince1970: Double(slot) * readingInterval)
    }

    private static func plannedGlucose(from start: Date, to end: Date) -> [PlannedGlucose] {
        stride(from: slot(of: start), through: slot(of: end), by: 1).map { index in
            let slotDate = date(ofSlot: index)
            let value = glucoseValue(at: slotDate)
            let previous = glucoseValue(at: slotDate.addingTimeInterval(-readingInterval))
            return PlannedGlucose(
                id: id(.glucose, at: slotDate),
                date: slotDate,
                value: value,
                direction: direction(from: previous, to: value)
            )
        }
    }

    /// The generated curve: a circadian swing, a faster ripple, a little noise, and a rise and
    /// fall around every meal. Shaped rather than random so the things that read the curve —
    /// the smoothed line, the peak badges, the excursion lane — all have something to find.
    private static func glucoseValue(at date: Date) -> Int16 {
        let seconds = date.timeIntervalSince1970
        let circadian = sin(seconds / 86400 * 2 * .pi) * 22
        let ripple = sin(seconds / 9000 * 2 * .pi) * 16
        let jitter = (noise(UInt64(bitPattern: Int64(slot(of: date)))) - 0.5) * 12
        let value = 118 + circadian + ripple + jitter + mealExcursion(at: date)
        return Int16(min(max(value.rounded(), 40), 400))
    }

    /// The bump a meal puts on the curve: a rise over the first hour, then a slow return over
    /// the next three.
    private static func mealExcursion(at date: Date) -> Double {
        var total: Double = 0
        for meal in meals(around: date) {
            let elapsed = date.timeIntervalSince(meal.date)
            guard elapsed >= 0, elapsed < 4 * 3600 else { continue }
            let peak = meal.carbs * 1.1
            if elapsed < 3600 {
                total += peak * (elapsed / 3600)
            } else {
                total += peak * (1 - (elapsed - 3600) / (3 * 3600))
            }
        }
        return total
    }

    private static func direction(from previous: Int16, to current: Int16) -> BloodGlucose.Direction {
        let delta = Int(current) - Int(previous)
        if delta <= -10 { return .doubleDown }
        if delta <= -5 { return .singleDown }
        if delta <= -2 { return .fortyFiveDown }
        if delta <= 1 { return .flat }
        if delta <= 4 { return .fortyFiveUp }
        if delta <= 9 { return .singleUp }
        return .doubleUp
    }

    // MARK: - Meals

    private struct Meal {
        let date: Date
        let carbs: Double
        let fat: Double
        let protein: Double
        let bolus: Decimal
        /// Hours of FPU entries this meal spreads out behind it, as the real splitter does.
        let fpuHours: Int
    }

    /// Meals of the calendar day `date` falls in, plus the day before — the excursion of last
    /// night's dinner still reaches into this morning.
    private static func meals(around date: Date) -> [Meal] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return meals(onDayStarting: calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay)
            + meals(onDayStarting: startOfDay)
    }

    /// A day's worth: breakfast, a lunch and a dinner big enough to carry fat and protein, and
    /// a late snack. Fixed rather than random, so every run of the seeder tells the same story.
    private static func meals(onDayStarting startOfDay: Date) -> [Meal] {
        [
            Meal(date: startOfDay.addingTimeInterval(7.5 * 3600), carbs: 42, fat: 8, protein: 12, bolus: 4.2, fpuHours: 0),
            Meal(date: startOfDay.addingTimeInterval(12.5 * 3600), carbs: 68, fat: 26, protein: 30, bolus: 6.8, fpuHours: 5),
            Meal(date: startOfDay.addingTimeInterval(18.5 * 3600), carbs: 85, fat: 34, protein: 38, bolus: 8.5, fpuHours: 6),
            Meal(date: startOfDay.addingTimeInterval(22 * 3600), carbs: 18, fat: 4, protein: 3, bolus: 1.8, fpuHours: 0)
        ]
    }

    /// The days the window touches, one start-of-day each.
    private static func dayStarts(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    // MARK: - Doses

    /// Every seeded bolus: one per meal, a dense burst in each day's storm window, and a
    /// background SMB every 20 minutes the rest of the time.
    private static func plannedDoses(from start: Date, to end: Date) -> [PlannedDose] {
        var doses: [PlannedDose] = []

        for day in dayStarts(from: start, to: end) {
            for meal in meals(onDayStarting: day) where (start ... end).contains(meal.date) {
                doses.append(PlannedDose(
                    id: id(.bolus, at: meal.date),
                    date: meal.date,
                    amount: meal.bolus,
                    isSMB: false
                ))
            }
            doses += stormDoses(onDayStarting: day, within: start ... end)
            doses += labelStormDoses(onDayStarting: day, within: start ... end)
        }

        // Background microboluses. Quantized to the reading grid so they land on the curve
        // rather than between its points.
        let step = Int(backgroundSMBInterval / readingInterval)
        for index in stride(from: slot(of: start), through: slot(of: end), by: step) {
            let slotDate = date(ofSlot: index)
            guard !isInStormWindow(slotDate) else { continue } // the storm already covers it
            doses.append(PlannedDose(
                id: id(.smb, at: slotDate),
                date: slotDate,
                amount: doseAmount(base: 0.05, spread: 0.45, seed: UInt64(bitPattern: Int64(index)) &+ 7),
                isSMB: true
            ))
        }

        return doses
    }

    /// The requested stress case: a window where an SMB lands at every single CGM reading, so
    /// the markers, their labels and the collision handling all meet a genuinely crowded
    /// stretch instead of the comfortable spacing of ordinary data.
    private static func stormDoses(onDayStarting day: Date, within range: ClosedRange<Date>) -> [PlannedDose] {
        let start = day.addingTimeInterval(stormStartHour * 3600)
        let step = Int(stormInterval / readingInterval)
        let end = start.addingTimeInterval(stormLength(onDayStarting: day))
        return stride(from: slot(of: start), to: slot(of: end), by: step)
            .map { date(ofSlot: $0) }
            .filter { range.contains($0) }
            .map { slotDate in
                // A spread that straddles the label threshold, so both the labelled and the
                // bare marker paths are exercised inside one cluster.
                PlannedDose(
                    id: id(.smb, at: slotDate),
                    date: slotDate,
                    amount: doseAmount(
                        base: 0.05,
                        spread: 0.75,
                        seed: UInt64(bitPattern: Int64(slot(of: slotDate))) &+ 13
                    ),
                    isSMB: true
                )
            }
    }

    /// A dose in whole hundredths of a unit, so it stores as cleanly as one the pump would
    /// actually have delivered.
    private static func doseAmount(base: Double, spread: Double, seed: UInt64) -> Decimal {
        Decimal(Int(((base + noise(seed) * spread) * 100).rounded())) / 100
    }

    /// A second, tighter storm — this one aimed at the amount *labels* rather than the markers.
    ///
    /// The SMB storm above is as dense as real data can get: one dose per CGM reading. This one
    /// is deliberately denser than reality, a dose every minute for an hour, and every dose in
    /// it is a whole unit or more — so it carries a label at every `BolusDisplayThreshold`
    /// setting, not just at "Show All". The amounts run up to two digits so the labels vary in
    /// width as well as in number.
    private static func labelStormDoses(onDayStarting day: Date, within range: ClosedRange<Date>) -> [PlannedDose] {
        let start = day.addingTimeInterval(labelStormStartHour * 3600)
        return stride(from: 0, to: stormLength(onDayStarting: day), by: labelStormInterval)
            .map { start.addingTimeInterval($0) }
            .filter { range.contains($0) }
            .map { doseDate in
                PlannedDose(
                    id: id(.bolus, at: doseDate),
                    date: doseDate,
                    amount: doseAmount(
                        base: 1.0,
                        spread: 8.9,
                        seed: UInt64(max(doseDate.timeIntervalSince1970, 0)) &+ 29
                    ),
                    isSMB: false
                )
            }
    }

    /// Mid-morning, clear of both the meals and the SMB storm, so the label pile-up is the only
    /// thing going on in that stretch and is easy to pan to. At its longest it ends at noon,
    /// half an hour before lunch.
    private static let labelStormStartHour: Double = 9
    /// Five doses per CGM reading — past what real data does, which is the point.
    private static let labelStormInterval: TimeInterval = 60

    /// How long a day's storms run. Both windows take the same length on the same day and
    /// cycle 1 h, 2 h, 3 h, so a 72 h seed always contains one of each: a short burst that only
    /// resolves when zoomed in, and a stretch wide enough to fill half the viewport at 6 h.
    /// Nothing about a crowded region behaves the same at both widths, so a single fixed length
    /// would only ever test one of them.
    private static func stormLength(onDayStarting day: Date) -> TimeInterval {
        let lengths: [TimeInterval] = [1 * 3600, 2 * 3600, 3 * 3600]
        let dayIndex = Int((day.timeIntervalSince1970 / 86400).rounded(.down))
        return lengths[((dayIndex % lengths.count) + lengths.count) % lengths.count]
    }

    /// Whether a date falls in its day's SMB storm — the window background microboluses stand
    /// out of, so the burst is the only thing in it.
    private static func isInStormWindow(_ date: Date) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(startOfDay) - stormStartHour * 3600
        return elapsed >= 0 && elapsed < stormLength(onDayStarting: startOfDay)
    }

    /// Straight after lunch, where a real SMB burst would fall.
    private static let stormStartHour: Double = 13
    /// One SMB per CGM reading — as dense as this chart can get.
    private static let stormInterval: TimeInterval = 300
    private static let backgroundSMBInterval: TimeInterval = 20 * 60

    // MARK: - Carbs and FPUs

    private static func plannedCarbs(from start: Date, to end: Date) -> [PlannedCarb] {
        var entries: [PlannedCarb] = []

        for day in dayStarts(from: start, to: end) {
            for meal in meals(onDayStarting: day) {
                if (start ... end).contains(meal.date) {
                    entries.append(PlannedCarb(
                        id: id(.carb, at: meal.date),
                        date: meal.date,
                        carbs: meal.carbs,
                        fat: meal.fat,
                        protein: meal.protein,
                        isFPU: false,
                        fpuID: meal.fpuHours > 0 ? id(.fpu, at: meal.date) : nil
                    ))
                }

                // The fat/protein tail, one entry an hour, as the real splitter writes it.
                guard meal.fpuHours > 0 else { continue }
                let batch = id(.fpu, at: meal.date)
                let perHour = (meal.fat * 9 + meal.protein * 4) / 10 / Double(meal.fpuHours)
                for hour in 1 ... meal.fpuHours {
                    let entryDate = meal.date.addingTimeInterval(Double(hour) * 3600)
                    guard (start ... end).contains(entryDate) else { continue }
                    entries.append(PlannedCarb(
                        id: id(.fpu, at: entryDate, index: hour),
                        date: entryDate,
                        carbs: (perHour * 10).rounded() / 10,
                        fat: 0,
                        protein: 0,
                        isFPU: true,
                        fpuID: batch
                    ))
                }
            }
        }

        return entries
    }

    // MARK: - Determinism

    /// A deterministic pseudo-random value in `0 ..< 1` from an integer seed.
    ///
    /// Deliberately not `random()`: a slot filled on one run and the same slot filled on a
    /// later one have to carry the same value, or a re-run would leave a visible seam wherever
    /// it stitched new data onto old.
    private static func noise(_ seed: UInt64) -> Double {
        var x = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        x ^= x >> 33
        x = x &* 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        return Double(x % 100_000) / 100_000
    }
}
