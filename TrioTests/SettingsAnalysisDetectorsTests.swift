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

    @Test("Low followed by a high is a rebound high") func testReboundHigh() {
        var history = History()
        history.glucose = cgm(10, 15) { hour in hour < 11 ? 60 : hour < 12 ? 120 : 210 }
        history.carbs = [SettingsAnalysis.CarbEvent(date: at(10.2), grams: 40)]

        let detection = detect(.reboundHigh, history)
        #expect(detection.occurrences.count == 1)
        #expect(detection.pattern.contains("20 g"))
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
