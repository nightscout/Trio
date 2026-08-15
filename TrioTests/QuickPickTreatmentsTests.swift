import Foundation
import Testing

@testable import Trio

@Suite("Quick-Pick Treatments: topQuickPickSuggestions") struct QuickPickTreatmentsTests {
    let cal = Calendar.current
    let now = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 8, minute: 0))!

    func daysAgo(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: -n, to: now)!
    }

    func isWeekend(_ date: Date) -> Bool {
        let weekday = cal.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    @Test("No samples yields no suggestions") func emptyHistoryYieldsNoSuggestions() {
        let result = topQuickPickSuggestions(from: [], roundingScale: 2, now: now)
        #expect(result.isEmpty)
    }

    @Test("Amounts rounding to the same key are grouped into a single suggestion") func roundingGroupsAmounts() {
        let samples = [
            QuickPickSample(amount: 2.01, timestamp: daysAgo(1)),
            QuickPickSample(amount: 1.99, timestamp: daysAgo(1))
        ]
        let result = topQuickPickSuggestions(from: samples, roundingScale: 0, now: now)
        #expect(result == [2])
    }

    @Test("A more recent sample outranks an older one at the same time of day") func recencyDecayFavorsNewerSamples() {
        let samples = [
            QuickPickSample(amount: 9, timestamp: daysAgo(20)),
            QuickPickSample(amount: 5, timestamp: daysAgo(7))
        ]
        let result = topQuickPickSuggestions(from: samples, roundingScale: 0, now: now, limit: 1)
        #expect(result == [5])
    }

    @Test(
        "A weekday-mismatched sample is weighted below the suggestion threshold that a matching one clears"
    ) func weekdayMismatchDropsBelowThreshold() {
        let matching = daysAgo(14)
        #expect(cal.component(.weekday, from: matching) == cal.component(.weekday, from: now))

        var mismatchOffset = 15
        while isWeekend(daysAgo(mismatchOffset)) == isWeekend(now) {
            mismatchOffset += 1
        }
        let mismatched = daysAgo(mismatchOffset)

        let matchingResult = topQuickPickSuggestions(
            from: [QuickPickSample(amount: 4, timestamp: matching)],
            roundingScale: 0,
            now: now
        )
        let mismatchedResult = topQuickPickSuggestions(
            from: [QuickPickSample(amount: 4, timestamp: mismatched)],
            roundingScale: 0,
            now: now
        )

        #expect(matchingResult == [4])
        #expect(mismatchedResult.isEmpty)
    }
}
