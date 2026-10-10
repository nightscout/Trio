import Foundation
import Testing

@testable import Trio

/// The stats screen's calendar-day interval takes a user-picked range. These pin the two
/// pure pieces that range feeds: how many whole days it covers, and which fixed interval's
/// bucket granularity the charts borrow to draw it.
@Suite("Stats: picked date range") struct StatRangePickerTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int) -> Date {
        let base = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000))
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    // MARK: - Day count

    @Test("A single day counts as one, not zero") func singleDayCountsAsOne() {
        #expect(Stat.StateModel.dayCount(of: day(0) ... day(0), calendar: calendar) == 1)
    }

    @Test("Both ends are included") func boundsAreInclusive() {
        #expect(Stat.StateModel.dayCount(of: day(0) ... day(6), calendar: calendar) == 7)
        #expect(Stat.StateModel.dayCount(of: day(0) ... day(1), calendar: calendar) == 2)
    }

    @Test("A time of day inside the bounds does not add a day") func ignoresTimeOfDay() {
        let almostMidnight = day(6).addingTimeInterval(23 * 3600 + 59 * 60)
        #expect(Stat.StateModel.dayCount(of: day(0) ... almostMidnight, calendar: calendar) == 7)
    }

    // MARK: - Chart granularity

    @Test("Range length picks the closest fixed interval", arguments: [
        (0, Stat.StateModel.StatsTimeInterval.day),
        (1, .week),
        (6, .week),
        (7, .month),
        (29, .month),
        (30, .total),
        (89, .total)
    ]) func granularityByLength(offset: Int, expected: Stat.StateModel.StatsTimeInterval) {
        #expect(Stat.StateModel.chartInterval(for: day(0) ... day(offset), calendar: calendar) == expected)
    }
}
