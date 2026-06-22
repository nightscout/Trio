import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: GlucoseAlertConfiguration.isNight") struct GlucoseAlertConfigurationTests {
    /// Fixed UTC calendar so date math is deterministic regardless of host TZ.
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Build a Date on a fixed day (2026-06-22) via the UTC calendar.
    private static func makeDate(hour: Int, minute: Int, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 22
        components.hour = hour
        components.minute = minute
        components.second = second
        return utcCalendar.date(from: components)!
    }

    // MARK: - Default window (day 06:00 / night 22:00, wrap)

    @Test("Default: 02:00 is night") func defaultEarlyMorningIsNight() {
        let config = GlucoseAlertConfiguration()
        #expect(config.isNight(at: Self.makeDate(hour: 2, minute: 0), calendar: Self.utcCalendar))
    }

    @Test("Default: 10:00 is day") func defaultMorningIsDay() {
        let config = GlucoseAlertConfiguration()
        #expect(!config.isNight(at: Self.makeDate(hour: 10, minute: 0), calendar: Self.utcCalendar))
    }

    @Test("Default: 14:00 is day") func defaultAfternoonIsDay() {
        let config = GlucoseAlertConfiguration()
        #expect(!config.isNight(at: Self.makeDate(hour: 14, minute: 0), calendar: Self.utcCalendar))
    }

    @Test("Default: 23:00 is night") func defaultLateEveningIsNight() {
        let config = GlucoseAlertConfiguration()
        #expect(config.isNight(at: Self.makeDate(hour: 23, minute: 0), calendar: Self.utcCalendar))
    }

    // MARK: - Boundary (default)

    @Test("Default boundary: 22:00:00 is night (nightStart inclusive)") func defaultNightStartInclusive() {
        let config = GlucoseAlertConfiguration()
        #expect(config.isNight(at: Self.makeDate(hour: 22, minute: 0, second: 0), calendar: Self.utcCalendar))
    }

    @Test("Default boundary: 06:00:00 is day (dayStart exclusive)") func defaultDayStartExclusive() {
        let config = GlucoseAlertConfiguration()
        #expect(!config.isNight(at: Self.makeDate(hour: 6, minute: 0, second: 0), calendar: Self.utcCalendar))
    }

    @Test("Default boundary: 05:59:59 is night") func defaultJustBeforeDayStartIsNight() {
        let config = GlucoseAlertConfiguration()
        #expect(config.isNight(at: Self.makeDate(hour: 5, minute: 59, second: 59), calendar: Self.utcCalendar))
    }

    @Test("Default boundary: 21:59:59 is day") func defaultJustBeforeNightStartIsDay() {
        let config = GlucoseAlertConfiguration()
        #expect(!config.isNight(at: Self.makeDate(hour: 21, minute: 59, second: 59), calendar: Self.utcCalendar))
    }

    // MARK: - Non-wrap config (dayStart 07:00, nightStart 01:00)

    @Test("Non-wrap: 03:00 is night") func nonWrapInsideNightIsNight() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 7, minute: 0),
            nightStart: TimeOfDay(hour: 1, minute: 0)
        )
        #expect(config.isNight(at: Self.makeDate(hour: 3, minute: 0), calendar: Self.utcCalendar))
    }

    @Test("Non-wrap: 12:00 is day") func nonWrapMiddayIsDay() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 7, minute: 0),
            nightStart: TimeOfDay(hour: 1, minute: 0)
        )
        #expect(!config.isNight(at: Self.makeDate(hour: 12, minute: 0), calendar: Self.utcCalendar))
    }

    @Test("Non-wrap: 00:30 is day (before nightStart)") func nonWrapBeforeNightStartIsDay() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 7, minute: 0),
            nightStart: TimeOfDay(hour: 1, minute: 0)
        )
        #expect(!config.isNight(at: Self.makeDate(hour: 0, minute: 30), calendar: Self.utcCalendar))
    }

    @Test("Non-wrap boundary: 07:00:00 is day (dayStart exclusive)") func nonWrapDayStartExclusive() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 7, minute: 0),
            nightStart: TimeOfDay(hour: 1, minute: 0)
        )
        #expect(!config.isNight(at: Self.makeDate(hour: 7, minute: 0, second: 0), calendar: Self.utcCalendar))
    }

    @Test("Non-wrap boundary: 01:00:00 is night (nightStart inclusive)") func nonWrapNightStartInclusive() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 7, minute: 0),
            nightStart: TimeOfDay(hour: 1, minute: 0)
        )
        #expect(config.isNight(at: Self.makeDate(hour: 1, minute: 0, second: 0), calendar: Self.utcCalendar))
    }

    // MARK: - Degenerate equal (dayStart == nightStart == 06:00) — proves wrap >= branch

    @Test("Equal: 05:00 is night") func equalBeforeIsNight() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 6, minute: 0),
            nightStart: TimeOfDay(hour: 6, minute: 0)
        )
        #expect(config.isNight(at: Self.makeDate(hour: 5, minute: 0), calendar: Self.utcCalendar))
    }

    @Test("Equal: 06:00:00 is night (wrap >= branch)") func equalAtBoundaryIsNight() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 6, minute: 0),
            nightStart: TimeOfDay(hour: 6, minute: 0)
        )
        #expect(config.isNight(at: Self.makeDate(hour: 6, minute: 0, second: 0), calendar: Self.utcCalendar))
    }

    @Test("Equal: 10:00 is night") func equalAfterIsNight() {
        let config = GlucoseAlertConfiguration(
            dayStart: TimeOfDay(hour: 6, minute: 0),
            nightStart: TimeOfDay(hour: 6, minute: 0)
        )
        #expect(config.isNight(at: Self.makeDate(hour: 10, minute: 0), calendar: Self.utcCalendar))
    }
}
