import Foundation
import Testing

@testable import Trio

@Suite("Duration Formatting") struct DurationFormattingTests {
    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    @Test("Lengths round down, with hours and minutes under a day and days and hours from a day", arguments: [
        (0, "0m", "0min", "0 minutes"),
        (59, "<\u{00A0}1m", "<\u{00A0}1min", "<\u{00A0}1 minute"),
        (-30, "<\u{00A0}1m", "<\u{00A0}1min", "<\u{00A0}1 minute"),
        (89, "1m", "1min", "1 minute"),
        (7200, "2h", "2h", "2 hours"),
        (86399, "23h 59m", "23h 59min", "23 hours, 59 minutes"),
        (86400, "1d", "1j", "1 day"),
        (485_940, "5d 14h", "5j 14h", "5 days, 14 hours")
    ]) func timeSpan(seconds: Int, expected: String, expectedFrench: String, expectedSpoken: String) {
        let duration = Duration.seconds(seconds)
        #expect(duration.formattedTimeSpan(locale: english) == expected)
        #expect(duration.formattedTimeSpan(locale: french) == expectedFrench)
        #expect(duration.formattedSpokenTimeSpan(locale: english) == expectedSpoken)
    }

    // shortcut: reads the real clock, so the 1-day case can fail in the 24 hours after clocks go back;
    // pass a reference date (Date.AnchoredRelativeFormatStyle) once iOS 18 is the minimum.
    @Test("VoiceOver time ago matches the visible text under a day and names the calendar day after", arguments: [
        (30, "<\u{00A0}1m", "less than a minute ago"),
        (-30, "<\u{00A0}1m", "less than a minute ago"),
        (479, "7m", "7 minutes ago"),
        (10740, "2h 59m", "2 hours ago"),
        (86400, "1d", "yesterday")
    ]) func timeAgo(secondsAgo: Int, expected: String, expectedSpoken: String) {
        let date = Date(timeIntervalSinceNow: TimeInterval(-secondsAgo))
        #expect(date.formattedTimeAgo(locale: english) == expected)
        #expect(date.formattedSpokenTimeAgo(locale: english) == expectedSpoken)
    }

    @Test("Spoken time ago uses the locale's grammar") func spokenTimeAgoFrench() {
        #expect(Date(timeIntervalSinceNow: -479).formattedSpokenTimeAgo(locale: french) == "il y a 7 minutes")
    }

    @Test("Stored minutes clamp instead of trapping on corrupt values") func storedMinutes() {
        #expect(Duration(minutes: 90) == .seconds(5400))
        #expect(Duration(minutes: .nan) == .zero)
        #expect(Duration(minutes: -5) == .zero)
        #expect(Duration(minutes: Decimal(string: "1e30")!) == .seconds(Int(Int32.max) * 60))
    }
}
