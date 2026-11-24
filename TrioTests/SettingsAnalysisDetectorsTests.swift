import CoreData
import Foundation
import Testing
@testable import Trio

@Suite("Settings Analysis Detectors Tests") struct SettingsAnalysisDetectorsTests {
    typealias History = SettingsAnalysis.History
    typealias Point = SettingsAnalysis.GlucosePoint

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Midnight UTC, 2026-03-02.
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))! }

    private func at(_ hour: Double, dayOffset: Int = 0) -> Date {
        day.addingTimeInterval(Double(dayOffset) * 86400 + hour * 3600)
    }

    /// Readings every 5 min from `from` to `to` (hours), with the value given by `value(hour)`.
    private func cgm(_ from: Double, _ to: Double, dayOffset: Int = 0, _ value: (Double) -> Int) -> [Point] {
        stride(from: from, through: to, by: 5.0 / 60).map { Point(date: at($0, dayOffset: dayOffset), value: value($0)) }
    }

    private var dayFrame: SettingsAnalysis.TimeFrame {
        SettingsAnalysis.TimeFrame(start: day, end: day.addingTimeInterval(86400))
    }

    private func detect(
        _ scenario: SettingsAnalysis.Scenario,
        _ history: History,
        frame: SettingsAnalysis.TimeFrame? = nil
    ) -> SettingsAnalysis.Detection {
        SettingsAnalysis.Detectors(history: history, timeFrame: frame ?? dayFrame, units: .mgdL, calendar: calendar)
            .detect(scenario)
    }

    // MARK: Meal spike

    @Test("Meal followed by a large rise is a meal spike") func testMealSpike() {
        var history = History()
        history.glucose = cgm(7, 11) { hour in hour < 8 ? 110 : hour < 9 ? 110 + Int((hour - 8) * 120) : 230 }
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(8), grams: 50)]

        let detection = detect(.mealSpike, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.occurrences.first?.date == at(8))
        #expect(detection.pattern.contains("100"))
    }

    @Test("Meal with a small rise is not a meal spike") func testMealNoSpike() {
        var history = History()
        history.glucose = cgm(7, 11) { _ in 150 }
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(8), grams: 50)]
        #expect(detect(.mealSpike, history).occurrences.isEmpty)
    }

    // MARK: Lows

    @Test("Correction bolus followed by a low") func testBolusThenHypo() {
        var history = History()
        history.glucose = cgm(13, 18) { hour in hour < 16 ? 200 - Int((hour - 13) * 45) : 60 }
        history.boluses = [SettingsAnalysis.BolusEvent(date: at(14), units: 2, isSMB: false)]

        let detection = detect(.bolusThenHypo, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.pattern.contains("correction"))
    }

    @Test("SMBs and carbs after the bolus do not count as bolus then hypo") func testBolusThenHypoExclusions() {
        var history = History()
        history.glucose = cgm(13, 18) { hour in hour < 16 ? 200 - Int((hour - 13) * 45) : 60 }
        history.boluses = [SettingsAnalysis.BolusEvent(date: at(14), units: 2, isSMB: true)]
        #expect(detect(.bolusThenHypo, history).occurrences.isEmpty)

        history.boluses = [SettingsAnalysis.BolusEvent(date: at(14), units: 2, isSMB: false)]
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(15), grams: 20)]
        #expect(detect(.bolusThenHypo, history).occurrences.isEmpty)
    }

    @Test("A single low reading is not an episode") func testSingleLowReadingIgnored() {
        var history = History()
        history.glucose = cgm(1, 4) { hour in abs(hour - 2) < 0.01 ? 60 : 110 }
        #expect(detect(.overnightLow, history).occurrences.isEmpty)
    }

    @Test("Overnight low is found with its time window") func testOvernightLow() {
        var history = History()
        history.glucose = cgm(0, 6) { hour in (2 ... 2.5).contains(hour) ? 62 : 110 }

        let detection = detect(.overnightLow, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.occurrences.first?.detail.contains("62") == true)
        #expect(detection.pattern.contains("100%"))
    }

    // MARK: Nights

    @Test("Early-morning rise without treatments is dawn phenomenon") func testDawnPhenomenon() {
        var history = History()
        history.glucose = cgm(0, 9) { hour in hour < 4.5 ? 100 : min(100 + Int((hour - 4.5) * 40), 180) }

        let detection = detect(.dawnPhenomenon, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.pattern.contains("100%"))
    }

    @Test("A bolus during the night rules out dawn phenomenon") func testDawnPhenomenonExcludedByBolus() {
        var history = History()
        history.glucose = cgm(0, 9) { hour in hour < 4.5 ? 100 : min(100 + Int((hour - 4.5) * 40), 180) }
        history.boluses = [SettingsAnalysis.BolusEvent(date: at(5), units: 1, isSMB: false)]
        #expect(detect(.dawnPhenomenon, history).occurrences.isEmpty)
    }

    @Test("Nights with too few readings are skipped") func testDawnPhenomenonNeedsData() {
        var history = History()
        history.glucose = cgm(0, 9) { hour in hour < 4.5 ? 100 : 180 }.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        #expect(detect(.dawnPhenomenon, history).occurrences.isEmpty)
    }

    // MARK: Highs

    /// 150, climbing 40 mg/dL per hour from 09:00 to 230, staying there until 15:00.
    private func slowClimb(_ hour: Double) -> Int {
        hour < 9 ? 150 : hour < 11 ? 150 + Int((hour - 9) * 40) : hour <= 15 ? 230 : 150
    }

    @Test("Long high without carbs is persistent; site age becomes the pattern") func testPersistentHigh() {
        var history = History()
        history.glucose = cgm(8, 16, slowClimb)
        history.siteChanges = [at(9, dayOffset: -2)]

        let detection = detect(.persistentHigh, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.pattern.contains("day 3"))
    }

    @Test("A long high after a meal is not persistent") func testPersistentHighExcludedByCarbs() {
        var history = History()
        history.glucose = cgm(8, 16, slowClimb)
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(10.5), grams: 60)]
        #expect(detect(.persistentHigh, history).occurrences.isEmpty)
    }

    @Test("In range at 2 h, high at 4 h is a delayed meal rise") func testDelayedMealRise() {
        var history = History()
        history.glucose = cgm(18, 25) { hour in hour < 21.5 ? 140 : 210 }
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(18.5), grams: 70)]

        let detection = detect(.delayedMealRise, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.pattern.contains("dinner"))
        #expect(detect(.mealSpike, history).occurrences.isEmpty)
    }

    // MARK: Activity

    @Test("Fast drop during an activity target") func testExerciseDrop() {
        var history = History()
        history.glucose = cgm(16, 20) { hour in hour < 17.5 ? 180 : max(180 - Int((hour - 17.5) * 120), 90) }
        history.activity = [DateInterval(start: at(17), end: at(18.5))]
        history.iob = [SettingsAnalysis.IOBPoint(date: at(17.1), iob: 3)]

        let detection = detect(.exerciseDrop, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.pattern.contains("2 U"))
    }

    @Test("A drop outside any activity period is not an activity drop") func testExerciseDropNeedsActivity() {
        var history = History()
        history.glucose = cgm(16, 20) { hour in hour < 17.5 ? 180 : max(180 - Int((hour - 17.5) * 120), 90) }
        #expect(detect(.exerciseDrop, history).occurrences.isEmpty)
    }

    @Test("A temp target set right after a low is not activity") func testExerciseDropIgnoresPostLowTarget() {
        var history = History()
        // Low until 16:30, high temp target from 16:45, then a fast drop.
        history.glucose = cgm(16, 20) { hour in
            hour < 16.5 ? 60 : hour < 17.5 ? 180 : max(180 - Int((hour - 17.5) * 120), 90)
        }
        history.activity = [DateInterval(start: at(16.75), end: at(18.5))]
        #expect(detect(.exerciseDrop, history).occurrences.isEmpty)

        // The same target an hour later counts.
        history.activity = [DateInterval(start: at(17.25), end: at(18.5))]
        #expect(detect(.exerciseDrop, history).occurrences.count == 1)
    }

    // MARK: Unannounced meals

    /// 100 until 12:00, then +2 mg/dL per minute to 220, holding until 14:00.
    private func unannouncedLunch(_ hour: Double) -> Int {
        hour < 12 ? 100 : hour < 13 ? 100 + Int((hour - 12) * 120) : hour < 14 ? 220 : 150
    }

    private func smb(_ hour: Double, _ units: Double) -> SettingsAnalysis.BolusEvent {
        SettingsAnalysis.BolusEvent(date: at(hour), units: units, isSMB: true)
    }

    private func report(_ history: History) -> SettingsAnalysis.Report {
        SettingsAnalysis.Engine.report(
            history: history,
            timeFrame: dayFrame,
            snapshot: .defaults,
            catalog: nil,
            catalogError: nil,
            units: .mgdL
        )
    }

    @Test("Fast rise without carbs, covered only by SMBs, is an unannounced meal rise") func testUnannouncedMeal() {
        var history = History()
        history.glucose = cgm(11, 16, unannouncedLunch)
        history.boluses = [smb(12.25, 1), smb(12.5, 1.5)]

        let detection = detect(.unannouncedMeal, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.variant == .unannounced)
        let smbTotal = 2.5.formatted(.number.precision(.fractionLength(1)))
        #expect(detection.occurrences.first?.detail.contains(smbTotal) == true)
        #expect(detect(.mealSpike, history).occurrences.isEmpty)
    }

    @Test("A manual bolus before the rise is a prebolus") func testUnannouncedMealWithPrebolus() {
        var history = History()
        history.glucose = cgm(11, 16, unannouncedLunch)
        history.boluses = [SettingsAnalysis.BolusEvent(date: at(11.5), units: 3, isSMB: false), smb(12.5, 1)]

        let detection = detect(.unannouncedMeal, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.variant == .prebolus)
        #expect(detection.pattern.contains("prebolus"))
    }

    @Test("A rise with logged carbs is not unannounced") func testLoggedMealIsNotUnannounced() {
        var history = History()
        history.glucose = cgm(11, 16, unannouncedLunch)
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(11.9), grams: 60)]
        #expect(detect(.unannouncedMeal, history).occurrences.isEmpty)
    }

    @Test("A rise right after a low is a rebound, not a meal") func testReboundIsNotUnannounced() {
        var history = History()
        history.glucose = cgm(10, 15) { hour in hour < 11 ? 60 : hour < 12 ? 120 : 210 }
        let detectors = SettingsAnalysis.Detectors(history: history, timeFrame: dayFrame, units: .mgdL, calendar: calendar)
        #expect(detectors.inferredMeals.isEmpty)
    }

    @Test("A low after a prebolus-only meal is attributed to the prebolus") func testPrebolusThenHypo() {
        var history = History()
        history.glucose = cgm(11, 16) { hour in hour < 14.9 ? unannouncedLunch(hour) : 60 }
        history.boluses = [SettingsAnalysis.BolusEvent(date: at(11.5), units: 4, isSMB: false)]

        let detection = detect(.bolusThenHypo, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.variant == .prebolus)
        #expect(!detection.pattern.contains("correction"))
    }

    @Test("Unannounced breakfast is not dawn phenomenon") func testUnannouncedBreakfastIsNotDawn() {
        var history = History()
        history.glucose = cgm(0, 9) { hour in hour < 7 ? 100 : min(100 + Int((hour - 7) * 180), 220) }

        #expect(detect(.dawnPhenomenon, history).occurrences.isEmpty)
        #expect(detect(.unannouncedMeal, history).occurrences.count == 1)
    }

    @Test("A high that starts with an unannounced meal is not persistent") func testUnannouncedMealIsNotPersistentHigh() {
        var history = History()
        history
            .glucose = cgm(10, 17) { hour in
                hour < 11 ? 120 : hour < 11.5 ? 120 + Int((hour - 11) * 240) : hour < 15.5 ? 240 : 150 }

        #expect(detect(.persistentHigh, history).occurrences.isEmpty)
        #expect(detect(.unannouncedMeal, history).occurrences.count == 1)
    }

    @Test("Without logged meals, carb-based scenarios can't be checked") func testUnannouncedUserCantCheckCarbScenarios() {
        var history = History()
        history.glucose = cgm(0, 23.99, unannouncedLunch)

        let report = report(history)
        #expect(report.mealProfile.style == .unannounced)
        #expect(Set(report.unavailable.map(\.scenario)) == [.mealSpike, .delayedMealRise])
        #expect(!report.notDetected.contains(.mealSpike))
    }

    @Test("With some meals logged, carb-based findings get guard P12") func testPartialAnnouncerGetsP12() {
        var history = History()
        history.glucose = cgm(7, 11) { hour in hour < 8 ? 110 : hour < 9 ? 110 + Int((hour - 8) * 120) : 230 }
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(8), grams: 50)]

        let report = report(history)
        #expect(report.mealProfile.style == .partial)
        let spike = report.findings.first { $0.scenario == .mealSpike }
        #expect(spike?.guardIDs.contains("P12") == true)
        #expect(report.unavailable.isEmpty)
    }

    // MARK: Units

    @Test("Details and rules use the user's glucose units") func testMmolUnits() {
        var history = History()
        history.glucose = cgm(0, 6) { hour in (2 ... 2.5).contains(hour) ? 62 : 110 }
        let detection = SettingsAnalysis.Detectors(history: history, timeFrame: dayFrame, units: .mmolL, calendar: calendar)
            .detect(.overnightLow)
        let detail = detection.occurrences.first?.detail ?? ""
        #expect(detail.contains("mmol/L"))
        #expect(detail.contains(Decimal(3.4).formatted(.number.precision(.fractionLength(1)))))
        #expect(!detail.contains("mg/dL"))

        for scenario in SettingsAnalysis.Scenario.allCases {
            #expect(!scenario.detectionRule(units: .mmolL).contains("mg/dL"), "\(scenario) rule shows mg/dL")
        }
    }

    // MARK: Time frame and report

    @Test("Events before the time frame are not counted") func testOutsideFrame() {
        var history = History()
        history.glucose = cgm(2, 3, dayOffset: -1) { _ in 60 }
        #expect(detect(.overnightLow, history).occurrences.isEmpty)
    }

    @Test("Report counts readings, time in range and coverage") func testReportOverview() {
        var history = History()
        history.glucose = cgm(0, 23.99) { hour in hour < 6 ? 200 : 120 }

        let report = SettingsAnalysis.Engine.report(
            history: history,
            timeFrame: dayFrame,
            snapshot: .defaults,
            catalog: nil,
            catalogError: nil,
            units: .mgdL
        )
        #expect(report.readings == 288)
        #expect(report.timeInRange == 75)
        #expect(report.coverage == 100)
        #expect(
            report.findings.count + report.notDetected.count + report.unavailable.count ==
                SettingsAnalysis.Scenario.allCases.count
        )
    }

    @Test("Empty history yields no findings and no time in range") func testEmptyReport() {
        let report = SettingsAnalysis.Engine.report(
            history: History(),
            timeFrame: dayFrame,
            snapshot: .defaults,
            catalog: nil,
            catalogError: nil,
            units: .mgdL
        )
        #expect(report.findings.isEmpty)
        #expect(report.timeInRange == nil)
        #expect(report.readings == 0)
    }

    @Test("Activity intervals are merged") func testMergeIntervals() {
        let merged = SettingsAnalysis.HistoryLoader.merge([
            DateInterval(start: at(10), end: at(11)),
            DateInterval(start: at(10.5), end: at(12)),
            DateInterval(start: at(14), end: at(15))
        ])
        #expect(merged == [DateInterval(start: at(10), end: at(12)), DateInterval(start: at(14), end: at(15))])
    }
}

/// Runs the loader against an in-memory store holding records the way the app writes them.
@Suite("Settings Analysis History Loader Tests", .serialized) struct SettingsAnalysisHistoryLoaderTests {
    let stack: CoreDataStack
    let context: NSManagedObjectContext

    /// Midnight UTC, 2026-03-02; the time frame is that day.
    let day = Date(timeIntervalSince1970: 1_772_409_600)
    var frame: SettingsAnalysis.TimeFrame { SettingsAnalysis.TimeFrame(start: day, end: day.addingTimeInterval(86400)) }

    init() async throws {
        stack = try await CoreDataStack.createForTests()
        context = stack.newTaskContext()
    }

    private func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }

    private func seed(_ build: @escaping (NSManagedObjectContext) -> Void) async throws {
        try await context.perform {
            build(context)
            try context.save()
        }
    }

    private func load() async -> SettingsAnalysis.History {
        await SettingsAnalysis.HistoryLoader.load(frame, context: context)
    }

    private static func glucose(_ value: Int, at date: Date, manual: Bool = false, in context: NSManagedObjectContext) {
        let row = GlucoseStored(context: context)
        row.id = UUID()
        row.date = date
        row.glucose = Int16(value)
        row.isManual = manual
    }

    private static func bolus(_ units: Double, at date: Date, smb: Bool, in context: NSManagedObjectContext) {
        let event = PumpEventStored(context: context)
        event.id = UUID().uuidString
        event.timestamp = date
        event.type = smb ? PumpEventStored.EventType.smb.rawValue : PumpEventStored.EventType.bolus.rawValue
        let bolus = BolusStored(context: context)
        bolus.amount = NSDecimalNumber(value: units)
        bolus.isSMB = smb
        bolus.pumpEvent = event
    }

    private static func pumpEvent(_ type: PumpEventStored.EventType, at date: Date, in context: NSManagedObjectContext) {
        let event = PumpEventStored(context: context)
        event.id = UUID().uuidString
        event.timestamp = date
        event.type = type.rawValue
    }

    @Test("Glucose, carbs, boluses and site changes are read from the store") func testTreatments() async throws {
        try await seed { context in
            Self.glucose(110, at: at(8), in: context)
            Self.glucose(120, at: at(8.1), in: context)
            Self.glucose(95, at: at(9), manual: true, in: context)
            Self.glucose(300, at: at(-12), in: context) // before the lookback

            let meal = CarbEntryStored(context: context)
            meal.date = at(12)
            meal.carbs = 40
            meal.isFPU = false
            let fpu = CarbEntryStored(context: context)
            fpu.date = at(14)
            fpu.carbs = 20
            fpu.isFPU = true

            Self.bolus(3, at: at(12), smb: false, in: context)
            Self.bolus(0.4, at: at(12.5), smb: true, in: context)
            Self.pumpEvent(.tempBasal, at: at(13), in: context)
            Self.pumpEvent(.rewind, at: at(20), in: context)
            Self.pumpEvent(.prime, at: at(20.1), in: context)
        }

        let history = await load()
        #expect(history.glucose.map(\.value) == [110, 120])
        #expect(history.carbs == [SettingsAnalysis.CarbEvent(date: at(12), grams: 40)])
        #expect(history.boluses.map(\.isSMB) == [false, true])
        #expect(history.boluses.map(\.units) == [3, 0.4])
        #expect(history.siteChanges == [at(20)])
        #expect(history.activity.isEmpty)
        #expect(history.iob.isEmpty)
    }

    @Test("Activity periods come from runs and rows the way adjustments are stored") func testActivity() async throws {
        try await seed { context in
            // A preset that ran twice: the older run lost its link when the preset ran again.
            let exercise = OverrideStored(context: context)
            exercise.id = UUID().uuidString
            exercise.name = "Exercise"
            exercise.isPreset = true
            exercise.enabled = false
            exercise.percentage = 50
            exercise.date = at(17)
            exercise.duration = 60
            for (start, end, linked) in [(at(8), at(9), false), (at(17), at(18), true)] {
                let run = OverrideRunStored(context: context)
                run.id = UUID()
                run.name = "Exercise"
                run.startDate = start
                run.endDate = end
                run.target = 0
                if linked { run.override = exercise }
            }

            // A one-off 60 min temp target cancelled after 20 min.
            let target = TempTargetStored(context: context)
            target.id = UUID()
            target.isPreset = false
            target.enabled = false
            target.target = 140
            target.date = at(12)
            target.duration = 60
            let targetRun = TempTargetRunStored(context: context)
            targetRun.id = UUID()
            targetRun.startDate = at(12)
            targetRun.endDate = at(12) + 20 * 60
            targetRun.target = 140
            targetRun.tempTarget = target

            // A preset that is not about activity.
            let sleep = OverrideStored(context: context)
            sleep.id = UUID().uuidString
            sleep.name = "Sleep"
            sleep.isPreset = true
            sleep.enabled = false
            sleep.percentage = 100
            sleep.target = 100
            let sleepRun = OverrideRunStored(context: context)
            sleepRun.id = UUID()
            sleepRun.name = "Sleep"
            sleepRun.startDate = at(1)
            sleepRun.endDate = at(6)
            sleepRun.target = 100
            sleepRun.override = sleep

            // Indefinite reduced-insulin override still running since two days before the frame.
            let running = OverrideStored(context: context)
            running.id = UUID().uuidString
            running.isPreset = false
            running.enabled = true
            running.indefinite = true
            running.percentage = 80
            running.date = at(-48)
        }

        let history = await load()
        // The running override covers the whole frame (from its start), so check it separately.
        #expect(history.activity == [DateInterval(start: at(-48), end: frame.end)])

        try await context.perform {
            let request: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            request.predicate = NSPredicate(format: "indefinite == YES")
            for row in try context.fetch(request) { context.delete(row) }
            try context.save()
        }
        let withoutRunning = await load()
        #expect(withoutRunning.activity == [
            DateInterval(start: at(8), end: at(9)),
            DateInterval(start: at(12), end: at(12) + 20 * 60),
            DateInterval(start: at(17), end: at(18))
        ])
    }

    @Test("Stored records run through the whole analysis") func testEndToEnd() async throws {
        try await seed { context in
            // Every 5 min: low at 02:00–03:00, meal spike after 12:00, fast drop during the 17:00 exercise.
            for step in stride(from: 0.0, through: 24, by: 5.0 / 60) {
                let value: Int
                switch step {
                case 2 ..< 3: value = 60
                case 12.5 ..< 14: value = 230
                case 17.5 ..< 18: value = 90
                default: value = 150
                }
                Self.glucose(value, at: at(step), in: context)
            }
            let meal = CarbEntryStored(context: context)
            meal.date = at(12)
            meal.carbs = 50
            meal.isFPU = false
            for hour in [7.5, 19.0] {
                let other = CarbEntryStored(context: context)
                other.date = at(hour)
                other.carbs = 30
                other.isFPU = false
            }
            Self.bolus(4, at: at(12), smb: false, in: context)

            let exercise = OverrideStored(context: context)
            exercise.id = UUID().uuidString
            exercise.name = "Exercise"
            exercise.isPreset = true
            exercise.enabled = false
            exercise.percentage = 50
            let run = OverrideRunStored(context: context)
            run.id = UUID()
            run.name = "Exercise"
            run.startDate = at(16.9)
            run.endDate = at(18)
            run.target = 0
            run.override = exercise
        }

        var engine = SettingsAnalysis.Engine(units: .mgdL)
        let context = self.context
        engine.loadHistory = {
            await SettingsAnalysis.HistoryLoader.load($0, exerciseAdjustments: $1, context: context)
        }
        let report = await engine.analyze(timeFrame: frame, snapshot: .defaults, catalog: nil, catalogError: nil)

        let found = Set(report.findings.map(\.scenario))
        #expect(found.contains(.overnightLow))
        #expect(found.contains(.mealSpike))
        #expect(found.contains(.exerciseDrop))
        #expect(!found.contains(.unannouncedMeal))
        #expect(report.readings == 289)

        // The user marks nothing as exercise: no activity drop.
        let usages = await SettingsAnalysis.HistoryLoader.adjustmentUsages(now: frame.end, context: context)
        #expect(usages.map(\.adjustment.name) == ["Exercise"])
        let excluded = await engine.analyze(
            timeFrame: frame,
            exerciseAdjustments: [],
            snapshot: .defaults,
            catalog: nil,
            catalogError: nil
        )
        #expect(!excluded.findings.map(\.scenario).contains(.exerciseDrop))
    }

    @Test("Adjustments are grouped by name, or by values when unnamed") func testAdjustmentUsages() {
        typealias Adjustment = SettingsAnalysis.Adjustment
        let afterLow = Adjustment(kind: .tempTarget, name: "After Low", target: 150)
        let custom140 = Adjustment(kind: .tempTarget, name: "Custom Temp Target", target: 140)
        let unnamed140 = Adjustment(kind: .tempTarget, name: nil, target: 140)
        let custom120 = Adjustment(kind: .tempTarget, name: "", target: 120)
        #expect(custom140 == unnamed140)
        #expect(custom140 != custom120)
        #expect(custom140.name == nil)

        func period(_ adjustment: Adjustment, _ hour: Double) -> SettingsAnalysis.AdjustmentPeriod {
            .init(adjustment: adjustment, interval: DateInterval(start: at(hour), duration: 1800))
        }
        var history = SettingsAnalysis.History()
        history.adjustments = [
            period(afterLow, 3), period(custom140, 8), period(afterLow, 10), period(unnamed140, 15), period(custom120, 17)
        ]
        let usages = SettingsAnalysis.AdjustmentUsage.usages(of: history.adjustments, in: frame)
        #expect(usages.map(\.count) == [2, 2, 1])
        #expect(usages.first(where: { $0.adjustment == afterLow })?.duration == 3600)

        // Until the user picks, raised temp targets count.
        history.selectExercise(nil)
        #expect(history.activity.map(\.start) == [at(3), at(8), at(10), at(15), at(17)])
        // Only the ones marked as exercise count.
        history.selectExercise([custom140.id, custom120.id])
        #expect(history.activity.map(\.start) == [at(8), at(15), at(17)])

        // Unused presets are listed too, after the used ones.
        let sport = Adjustment(kind: .override, name: "Sport", target: nil, percentage: 70)
        let withPresets = SettingsAnalysis.AdjustmentUsage.usages(of: history.adjustments, presets: [afterLow, sport], in: frame)
        #expect(withPresets.map(\.count) == [2, 2, 1, 0])
        #expect(withPresets.last?.adjustment == sport)
    }
}
