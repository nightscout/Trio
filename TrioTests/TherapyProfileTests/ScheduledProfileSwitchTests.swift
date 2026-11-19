import Foundation
import Testing
@testable import Trio

@Suite("Scheduled Profile Switch Tests") struct ScheduledProfileSwitchTests {
    private let weekend = ScheduledProfileSwitch(id: "w", profileName: "Weekend", weekday: 7, time: 25200)
    private let school = ScheduledProfileSwitch(id: "s", profileName: "Default", weekday: 2, time: 21600)

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ text: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func paused(_ entry: ScheduledProfileSwitch) -> ScheduledProfileSwitch {
        var entry = entry
        entry.paused = true
        return entry
    }

    @Test("Fingerprint matches the shared test vectors") func fingerprintVectors() {
        let entries = [weekend, school]
        #expect(
            [ScheduledProfileSwitch].fingerprintCanonicalString(of: entries) ==
                "profile=Default;weekday=2;date=-;time=21600;paused=false|profile=Weekend;weekday=7;date=-;time=25200;paused=false"
        )
        #expect(entries.fingerprint == "1f4d16404c846d2f")

        let pausedEntries = entries.map(paused)
        #expect(
            [ScheduledProfileSwitch].fingerprintCanonicalString(of: pausedEntries) ==
                "profile=Default;weekday=2;date=-;time=21600;paused=true|profile=Weekend;weekday=7;date=-;time=25200;paused=true"
        )
        #expect(pausedEntries.fingerprint == "bc784950a457ba2c")
        #expect([ScheduledProfileSwitch]().fingerprint == "e3b0c44298fc1c14")
    }

    @Test("Ids and order do not change the fingerprint; Default matches by name and store key") func fingerprintIdentity() {
        let renumbered = [
            ScheduledProfileSwitch(id: "x", profileName: "Default", weekday: 2, time: 21600),
            ScheduledProfileSwitch(id: "y", profileName: "Weekend", weekday: 7, time: 25200)
        ]
        #expect(renumbered.fingerprint == [weekend, school].fingerprint)
        #expect([weekend, school].withStoreKeys.map(\.profileName) == ["Weekend", "default"])
        #expect([weekend, school].matchesFingerprint([weekend, school].withStoreKeys.fingerprint.uppercased()))
        #expect([weekend, school].matchesFingerprint("1f4d16404c846d2f"))
        #expect(![weekend, school].matchesFingerprint("bc784950a457ba2c"))
    }

    @Test("The newest occurrence in the window wins, across the week boundary") func newestOccurrence() {
        let stockholm = calendar("Europe/Stockholm")
        let entries = [weekend, school]
        // Friday to the next Tuesday covers Saturday 07:00 and Monday 06:00.
        let found = entries.newestOccurrence(
            after: date("2026-11-13 12:00", stockholm),
            upTo: date("2026-11-17 12:00", stockholm),
            calendar: stockholm
        )
        #expect(found?.entry == school)
        #expect(found?.date == date("2026-11-16 06:00", stockholm))

        #expect(entries.newestOccurrence(
            after: date("2026-11-16 06:00", stockholm),
            upTo: date("2026-11-17 12:00", stockholm),
            calendar: stockholm
        ) == nil)
        #expect(entries.newestOccurrence(
            after: date("2026-11-16 05:59", stockholm),
            upTo: date("2026-11-16 06:00", stockholm),
            calendar: stockholm
        )?.entry == school)
    }

    @Test("Occurrences are wall-clock times in the calendar's zone") func timeZones() {
        let newYork = calendar("America/New_York")
        let found = [weekend].newestOccurrence(
            after: date("2026-11-13 00:00", newYork),
            upTo: date("2026-11-14 07:00", newYork),
            calendar: newYork
        )
        #expect(found?.date == date("2026-11-14 07:00", newYork))
        #expect(
            [weekend].nextOccurrence(after: date("2026-11-14 07:00", newYork), calendar: newYork)?.date ==
                date("2026-11-21 07:00", newYork)
        )
    }

    @Test("A start in the hour daylight saving time skips runs at the first time after it") func springForward() {
        let stockholm = calendar("Europe/Stockholm")
        let night = ScheduledProfileSwitch(id: "n", profileName: "Night", weekday: 1, time: 9000)
        let next = [night].nextOccurrence(after: date("2026-03-28 12:00", stockholm), calendar: stockholm)
        #expect(next?.date == date("2026-03-29 03:00", stockholm))
        #expect([night].newestOccurrence(
            after: date("2026-03-28 12:00", stockholm),
            upTo: date("2026-03-29 03:30", stockholm),
            calendar: stockholm
        )?.date == date("2026-03-29 03:00", stockholm))
    }

    @Test("A start in the hour daylight saving time repeats runs once") func fallBack() throws {
        let stockholm = calendar("Europe/Stockholm")
        let night = ScheduledProfileSwitch(id: "n", profileName: "Night", weekday: 1, time: 9000)
        let first = try #require([night].nextOccurrence(after: date("2026-10-24 12:00", stockholm), calendar: stockholm))
        #expect(stockholm.dateComponents([.month, .day, .hour, .minute], from: first.date) == DateComponents(
            month: 10,
            day: 25,
            hour: 2,
            minute: 30
        ))
        #expect(
            [night]
                .newestOccurrence(after: first.date, upTo: first.date.addingTimeInterval(7200), calendar: stockholm) == nil
        )
        #expect(
            [night].nextOccurrence(after: first.date, calendar: stockholm)?.date ==
                first.date.addingTimeInterval(7 * 86400 + 3600)
        )
    }

    @Test("A paused entry has no occurrences") func pausedEntries() {
        let stockholm = calendar("Europe/Stockholm")
        let entries = [paused(weekend), school]
        #expect(entries.newestOccurrence(
            after: date("2026-11-13 12:00", stockholm),
            upTo: date("2026-11-15 12:00", stockholm),
            calendar: stockholm
        ) == nil)
        #expect(entries.nextOccurrence(after: date("2026-11-13 12:00", stockholm), calendar: stockholm)?.entry == school)
        #expect(entries.map(paused).nextOccurrence(after: date("2026-11-13 12:00", stockholm), calendar: stockholm) == nil)
    }

    @Test("Renaming and removing a profile follow its entries") func renameAndRemove() {
        let entries = [weekend, school, ScheduledProfileSwitch(id: "w2", profileName: "Weekend", weekday: 1, time: 0)]
        #expect(entries.renamingProfile("Weekend", to: "Free").map(\.profileName) == ["Free", "Default", "Free"])
        #expect(entries.removingProfile("Weekend") == [school])
    }

    @Test("Entries are ordered as a week from Monday") func weekOrder() {
        let sunday = ScheduledProfileSwitch(id: "su", profileName: "A", weekday: 1, time: 0)
        let mondayLate = ScheduledProfileSwitch(id: "ml", profileName: "B", weekday: 2, time: 72000)
        #expect([sunday, weekend, mondayLate, school].sortedByWeek == [school, mondayLate, weekend, sunday])
    }
}
