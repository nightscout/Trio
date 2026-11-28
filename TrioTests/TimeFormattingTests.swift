import Foundation
import Testing

@testable import Trio

/// Styles that follow the locale run per locale; the rest stay in English so only the times vary.
@Suite("Time Formatting") struct TimeFormattingTests {
    private let english = Locale(identifier: "en_US")

    @Test("Time of day follows the locale's 12/24h clock", arguments: [
        ("en_US", "6:07\u{202F}AM"),
        ("en_GB@hours=h12", "6:07\u{202F}am"),
        ("ko_KR", "오전 6:07"),
        ("fr_FR", "06:07")
    ]) func timeOfDay(locale: String, expected: String) {
        #expect(date(hour: 6, minute: 7).formatted(.timeOfDay.locale(Locale(identifier: locale))) == expected)
    }

    @Test("Date and time adds a four-digit year to the time of day", arguments: [
        ("en_US", "1/5/2026, 6:07\u{202F}AM"),
        ("fr_FR", "05/01/2026 06:07")
    ]) func dateAndTime(locale: String, expected: String) {
        #expect(date(hour: 6, minute: 7).formatted(.dateAndTime.locale(Locale(identifier: locale))) == expected)
    }

    @Test("Minutes after midnight become a time of day", arguments: [
        (0, "12:00\u{202F}AM"),
        (390, "6:30\u{202F}AM"),
        (1410, "11:30\u{202F}PM")
    ]) func minuteOfDay(minutes: Int, expected: String) {
        #expect(Date(minuteOfDay: minutes).formatted(.timeOfDay.locale(english)) == expected)
    }

    @Test("Hour range spans the clock hour the date falls in", arguments: [
        (14, 37, "2:00\u{202F}PM – 3:00\u{202F}PM"),
        (23, 30, "11:00\u{202F}PM – 12:00\u{202F}AM")
    ]) func hourRange(hour: Int, minute: Int, expected: String) {
        #expect(date(hour: hour, minute: minute).formattedHourRange(locale: english) == expected)
    }

    @Test("SMB-off hours match when DosingEngine turns SMBs off", arguments: [
        (22, 6, String?("10:00\u{202F}PM – 6:00\u{202F}AM")),
        (14, 14, "2:00\u{202F}PM – 3:00\u{202F}PM"),
        (23, 23, "11:00\u{202F}PM – 12:00\u{202F}AM"),
        (0, 0, nil)
    ]) func smbOffHours(start: Int, end: Int, expected: String?) {
        #expect(OverrideStored.smbOffHours(start: start, end: end, locale: english) == expected)
    }

    /// 5 January 2026 at the given local time.
    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: hour, minute: minute))!
    }
}
