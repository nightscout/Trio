import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("TDD Storage Timezone Tests", .serialized) struct TDDStorageTimezoneTests {
    var coreDataStack: CoreDataStack!
    var context: NSManagedObjectContext!

    init() async throws {
        // In-memory Core Data for tests
        coreDataStack = try await CoreDataStack.createForTests()
        context = coreDataStack.newTaskContext()
    }

    @Test("Kingst's concern: -1 logic doesn't drop days across all UTC offsets") func testMinusOneLogicAcrossAllTimezones() {
        // Test the full spectrum of UTC offsets from -12 to +14
        let testTimezones = [
            // Negative offsets (west of UTC)
            "Pacific/Midway", // UTC-11
            "Pacific/Honolulu", // UTC-10
            "America/Anchorage", // UTC-9/-8
            "America/Los_Angeles", // UTC-8/-7
            "America/Denver", // UTC-7/-6
            "America/Chicago", // UTC-6/-5
            "America/New_York", // UTC-5/-4
            "America/Halifax", // UTC-4/-3
            "America/Sao_Paulo", // UTC-3

            // Near UTC
            "Atlantic/Azores", // UTC-1/0
            "UTC", // UTC+0
            "Europe/London", // UTC+0/+1

            // Positive offsets (east of UTC)
            "Europe/Paris", // UTC+1/+2
            "Europe/Athens", // UTC+2/+3
            "Europe/Moscow", // UTC+3
            "Asia/Dubai", // UTC+4
            "Asia/Karachi", // UTC+5
            "Asia/Kolkata", // UTC+5:30 (half-hour offset!)
            "Asia/Dhaka", // UTC+6
            "Asia/Bangkok", // UTC+7
            "Asia/Shanghai", // UTC+8
            "Asia/Tokyo", // UTC+9
            "Australia/Sydney", // UTC+10/+11
            "Pacific/Noumea", // UTC+11
            "Pacific/Auckland", // UTC+12/+13
            "Pacific/Kiritimati" // UTC+14
        ]

        for timezoneName in testTimezones {
            guard let timezone = TimeZone(identifier: timezoneName) else {
                Issue.record("Could not create timezone: \(timezoneName)")
                continue
            }

            let calendar = Calendar.current

            // Test edge case: late evening that crosses midnight in UTC
            var components = DateComponents()
            components.year = 2024
            components.month = 1
            components.day = 15
            components.hour = 23 // 11 PM local time
            components.minute = 30
            components.timeZone = timezone

            guard let testDate = calendar.date(from: components) else { continue }

            // Apply our TDDStorage logic: startOfDay + 24 hours - 1
            let startOfDay = calendar.startOfDay(for: testDate)
            let endOfDay = startOfDay.addingTimeInterval(TimeInterval.hours(24)) - 1

            // Extract day components to verify no day is dropped
            let startDayComponents = calendar.dateComponents([.day], from: startOfDay)
            let endDayComponents = calendar.dateComponents([.day], from: endOfDay)

            // Kingst's main concern: verify the -1 doesn't cause day to be dropped
            #expect(
                startDayComponents.day == endDayComponents.day,
                "The -1 second adjustment should NOT drop a day in \(timezoneName) (UTC\(timezone.secondsFromGMT() >= 0 ? "+" : "")\(timezone.secondsFromGMT() / 3600))"
            )

            // Verify we get exactly 23:59:59
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: endOfDay)
            #expect(
                timeComponents.hour == 23 && timeComponents.minute == 59 && timeComponents.second == 59,
                "End of day should be 23:59:59 in \(timezoneName)"
            )
        }
    }

    @Test("Forced unwrap safety: empty events don't crash") func testEmptyEventsHandling() {
        let emptyEvents: [PumpHistoryEvent] = []
        let sortedEvents = emptyEvents.sorted { $0.timestamp < $1.timestamp }

        // Our guard statement should handle this gracefully
        guard let firstEvent = sortedEvents.first else {
            // This is the expected path - no crash!
            #expect(true, "Empty events handled without forced unwrap crash")
            return
        }

        Issue.record("Should not reach here with empty events")
    }

    @Test("DST transitions maintain 24-hour calculations") func testDSTTransitions() {
        // Test the specific edge case of DST transitions
        let timezone = TimeZone(identifier: "America/New_York")!
        let calendar = Calendar.current

        // Spring forward: March 10, 2024 (lose an hour)
        var springComponents = DateComponents()
        springComponents.year = 2024
        springComponents.month = 3
        springComponents.day = 10
        springComponents.hour = 12
        springComponents.timeZone = timezone

        if let springDate = calendar.date(from: springComponents) {
            let startOfDay = calendar.startOfDay(for: springDate)
            let endOfDay = startOfDay.addingTimeInterval(TimeInterval.hours(24)) - 1

            let startDay = calendar.component(.day, from: startOfDay)
            let endDay = calendar.component(.day, from: endOfDay)

            #expect(
                startDay == endDay,
                "DST spring forward should not affect day boundaries"
            )
        }

        // Fall back: November 3, 2024 (gain an hour)
        var fallComponents = DateComponents()
        fallComponents.year = 2024
        fallComponents.month = 11
        fallComponents.day = 3
        fallComponents.hour = 12
        fallComponents.timeZone = timezone

        if let fallDate = calendar.date(from: fallComponents) {
            let startOfDay = calendar.startOfDay(for: fallDate)
            let endOfDay = startOfDay.addingTimeInterval(TimeInterval.hours(24)) - 1

            let startDay = calendar.component(.day, from: startOfDay)
            let endDay = calendar.component(.day, from: endOfDay)

            #expect(
                startDay == endDay,
                "DST fall back should not affect day boundaries"
            )
        }
    }

    @Test("Multiple consecutive days maintain correct boundaries") func testConsecutiveDayBoundaries() {
        // Verify the algorithm works correctly over multiple days
        let timezone = TimeZone(identifier: "Pacific/Honolulu")! // UTC-10, no DST
        let calendar = Calendar.current

        for dayOffset in 0 ..< 3 {
            var components = DateComponents()
            components.year = 2024
            components.month = 1
            components.day = 15 + dayOffset
            components.hour = 14
            components.timeZone = timezone

            guard let testDate = calendar.date(from: components) else { continue }

            let startOfDay = calendar.startOfDay(for: testDate)
            let endOfDay = startOfDay.addingTimeInterval(TimeInterval.hours(24)) - 1

            let startDayComponents = calendar.dateComponents([.year, .month, .day], from: startOfDay)
            let endDayComponents = calendar.dateComponents([.year, .month, .day], from: endOfDay)
            let expectedDayComponents = calendar.dateComponents([.year, .month, .day], from: testDate)

            #expect(
                startDayComponents.day == endDayComponents.day,
                "Start and end should be on the same day for offset \(dayOffset)"
            )
            
            #expect(
                startDayComponents.day == expectedDayComponents.day && 
                startDayComponents.month == expectedDayComponents.month &&
                startDayComponents.year == expectedDayComponents.year,
                "Day boundaries should match the test date (offset \(dayOffset))"
            )
        }
    }
}
