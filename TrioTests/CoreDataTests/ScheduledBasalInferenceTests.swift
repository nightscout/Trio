import Foundation
import Testing

@testable import Trio

/// Pure-function tests for the in-memory scheduled-basal timeline sweep:
/// uncovered gaps run the profile, suspensions never fill, nothing persists.
@Suite("Scheduled Basal Inference Tests") struct ScheduledBasalInferenceTests {
    typealias TimelineEvent = ScheduledBasalInference.TimelineEvent

    // MARK: - Fixtures

    private var flatProfile: [BasalProfileEntry] {
        [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0)]
    }

    // startOfDay-anchored so all times share one calendar day, matching the sweep's boundary math
    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func tempBasal(_ start: Date, _ end: Date) -> TimelineEvent {
        TimelineEvent(start: start, end: end, kind: .tempBasal)
    }

    private func totalDuration(_ segments: [ScheduledBasalInference.Segment]) -> TimeInterval {
        segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    private func isContiguous(_ segments: [ScheduledBasalInference.Segment]) -> Bool {
        zip(segments, segments.dropFirst()).allSatisfy { abs($0.end.timeIntervalSince($1.start)) < 1 }
    }

    private func near(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }

    // MARK: - Gap fill

    @Test("Gap after a temp basal is filled to now") func testFillsGapAfterTempBasal() {
        let segments = ScheduledBasalInference.segments(
            events: [tempBasal(time(9), time(9, 30))],
            profile: flatProfile,
            now: time(12)
        )

        #expect(!segments.isEmpty, "Uncovered gap must be filled")
        #expect(near(segments.first!.start, time(9, 30)), "Fill starts where the temp basal ends")
        #expect(near(segments.last!.end, time(12)), "Fill reaches now")
        #expect(isContiguous(segments), "Fill must not leave holes or overlaps")
        #expect(segments.allSatisfy { $0.rate == 1.0 }, "Rate comes from the profile")
    }

    @Test("Nothing is fabricated before the first event") func testNoFillBeforeFirstEvent() {
        let segments = ScheduledBasalInference.segments(
            events: [tempBasal(time(10), time(10, 30))],
            profile: flatProfile,
            now: time(12)
        )

        #expect(segments.allSatisfy { $0.start >= time(10, 30) }, "History before the first event is unknowable")
    }

    @Test("No events yields no segments") func testNoEvents() {
        let segments = ScheduledBasalInference.segments(events: [], profile: flatProfile, now: time(12))
        #expect(segments.isEmpty)
    }

    @Test("Empty profile yields no segments") func testEmptyProfile() {
        let segments = ScheduledBasalInference.segments(
            events: [tempBasal(time(9), time(9, 30))],
            profile: [],
            now: time(12)
        )
        #expect(segments.isEmpty)
    }

    @Test("Gaps below the minimum are ignored") func testMinGap() {
        let segments = ScheduledBasalInference.segments(
            events: [
                tempBasal(time(9), time(9, 30)),
                tempBasal(time(9, 30).addingTimeInterval(30), time(12))
            ],
            profile: flatProfile,
            now: time(12)
        )
        #expect(segments.isEmpty, "A 30-second gap is noise, not missing delivery")
    }

    @Test("Segments split at schedule boundaries with per-segment rates") func testSplitsAtScheduleBoundary() {
        let profile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "06:00", minutes: 360, rate: 2.0)
        ]
        let segments = ScheduledBasalInference.segments(
            events: [tempBasal(time(4), time(5))],
            profile: profile,
            now: time(7)
        )

        #expect(segments.count == 2, "Gap crossing one boundary yields two segments")
        #expect(near(segments[0].start, time(5)) && near(segments[0].end, time(6)))
        #expect(segments[0].rate == 1.0)
        #expect(near(segments[1].start, time(6)) && near(segments[1].end, time(7)))
        #expect(segments[1].rate == 2.0)
    }

    // MARK: - Suspensions

    @Test("Suspended spans are never filled") func testSuspensionNotFilled() {
        let segments = ScheduledBasalInference.segments(
            events: [
                tempBasal(time(8), time(8, 30)),
                TimelineEvent(start: time(9), kind: .suspend),
                TimelineEvent(start: time(10), kind: .resume)
            ],
            profile: flatProfile,
            now: time(12)
        )

        let suspended = DateInterval(start: time(9), end: time(10))
        #expect(
            segments.allSatisfy {
                (suspended.intersection(with: DateInterval(start: $0.start, end: $0.end))?.duration ?? 0) < 1
            },
            "No delivery happens while suspended"
        )
        #expect(abs(totalDuration(segments) - 2.5 * 3600) < 2, "Fill covers the 2.5 unsuspended hours")
    }

    @Test("An open suspend blocks fill until now") func testOpenSuspend() {
        let segments = ScheduledBasalInference.segments(
            events: [
                tempBasal(time(8), time(8, 30)),
                TimelineEvent(start: time(10), kind: .suspend)
            ],
            profile: flatProfile,
            now: time(12)
        )

        #expect(segments.allSatisfy { $0.end <= time(10).addingTimeInterval(1) }, "Nothing after the open suspend")
        #expect(abs(totalDuration(segments) - 1.5 * 3600) < 2, "Fill covers only the running span")
    }

    @Test("A leading resume implies the pump entered the window suspended") func testLeadingResumeSeedsSuspension() {
        let segments = ScheduledBasalInference.segments(
            events: [
                tempBasal(time(8), time(8, 30)),
                TimelineEvent(start: time(10), kind: .resume)
            ],
            profile: flatProfile,
            now: time(12)
        )

        // the suspend happened before the window; only 10:00-12:00 may fill
        #expect(
            segments.allSatisfy { $0.start >= time(10).addingTimeInterval(-1) },
            "Suspended span before the resume must not fill"
        )
        #expect(abs(totalDuration(segments) - 2 * 3600) < 2, "Fill covers resume to now")
    }

    @Test("A profile rate change inside a suspension does not leak fill") func testProfileRateChangeInsideSuspension() {
        let profile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "09:30", minutes: 570, rate: 2.0)
        ]
        let segments = ScheduledBasalInference.segments(
            events: [
                tempBasal(time(8), time(9)),
                TimelineEvent(start: time(9), kind: .suspend),
                TimelineEvent(start: time(10), kind: .resume)
            ],
            profile: profile,
            now: time(11)
        )

        // 09:30 boundary sits inside the suspension; only 10:00-11:00 may fill
        #expect(segments.count == 1)
        #expect(near(segments[0].start, time(10)) && near(segments[0].end, time(11)))
        #expect(segments[0].rate == 2.0)
    }

    // MARK: - Overlap handling

    @Test("A gap opens only past everything already covered") func testOverlappingEventsDoNotDoubleFill() {
        // short event contained inside a longer temp basal must not open a false gap
        let segments = ScheduledBasalInference.segments(
            events: [
                tempBasal(time(8), time(10)),
                tempBasal(time(8, 30), time(9))
            ],
            profile: flatProfile,
            now: time(12)
        )

        #expect(segments.count == 1)
        #expect(near(segments[0].start, time(10)), "Fill starts after the longest covering event")
        #expect(near(segments[0].end, time(12)))
    }
}
