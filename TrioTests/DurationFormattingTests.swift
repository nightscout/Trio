import Foundation
import Testing

@testable import Trio

@Suite("Duration Formatting") struct DurationFormattingTests {
    private let english = Locale(identifier: "en_US")

    @Test("Each style shows its units, rounded down", arguments: [
        (0, Duration.SpanStyle.exact, "0m", "0 minutes"),
        (59, .exact, "<\u{00A0}1m", "less than a minute"),
        (1530 * 60, .exact, "1d 1h 30m", "1 day, 1 hour, 30 minutes"),
        (86399, .largestTwoUnits, "23h 59m", "23 hours, 59 minutes"),
        (86400, .largestTwoUnits, "1d", "1 day"),
        (485_940, .largestTwoUnits, "5d 14h", "5 days, 14 hours"),
        (90 * 60, .minutes, "90m", "90 minutes")
    ]) func timeSpan(seconds: Int, style: Duration.SpanStyle, expected: String, expectedSpoken: String) {
        let duration = Duration.seconds(seconds)
        #expect(duration.formattedTimeSpan(style, locale: english) == expected)
        #expect(duration.formattedSpokenTimeSpan(style, locale: english) == expectedSpoken)
    }

    @Test("Time ago shows the two largest units, and VoiceOver reads the same span", arguments: [
        (30, "<\u{00A0}1m", "less than a minute ago"),
        (-30, "<\u{00A0}1m", "less than a minute ago"),
        (7140, "1h 59m", "1 hour, 59 minutes ago"),
        (172_740, "1d 23h", "1 day, 23 hours ago")
    ]) func timeAgo(secondsAgo: Int, expected: String, expectedSpoken: String) {
        let date = Date(timeIntervalSinceNow: TimeInterval(-secondsAgo))
        #expect(date.formattedTimeAgo(locale: english) == expected)
        #expect(date.formattedSpokenTimeAgo(locale: english) == expectedSpoken)
    }

    @Test("Locale formats the units; the words around them follow the app language") func locale() {
        let french = Locale(identifier: "fr_FR")
        #expect(Duration.seconds(5400).formattedTimeSpan(locale: french) == "1h 30min")
        #expect(Duration.seconds(30).formattedTimeSpan(locale: french) == "<\u{00A0}1min")
        #expect(Date(timeIntervalSinceNow: -7200).formattedSpokenTimeAgo(locale: french) == "2\u{00A0}heures ago")
    }

    @Test("Stored minutes clamp instead of trapping on corrupt values") func storedMinutes() {
        #expect(Duration(minutes: 90) == .seconds(5400))
        #expect(Duration(minutes: .nan) == .zero)
        #expect(Duration(minutes: -5) == .zero)
        #expect(Duration(minutes: Decimal(string: "1e30")!) == .seconds(Int(Int32.max) * 60))
    }
}
