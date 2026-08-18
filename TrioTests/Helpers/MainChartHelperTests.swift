import Foundation
import Testing
@testable import Trio

@Suite("Main Chart Helper Tests") struct MainChartHelperTests {
    @Test("Suspension terminates temp basal at suspend time") func tempBasalSegmentsAroundSuspension() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspensionStart = start.addingTimeInterval(300)
        let resume = start.addingTimeInterval(600)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspensionStart ... resume]
        )

        // TBR terminates at suspension start; no segment continues after
        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspensionStart, rate: 2.5)
        ])
    }

    @Test("Recalculation without suspension keeps the full temp basal") func tempBasalSegmentsAfterResume() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(900)
        let event = MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)

        let segments = MainChartHelper.tempBasalSegments(events: [event], suspensions: [])

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: end, rate: 2.5)
        ])
    }

    @Test("Active suspension terminates the temp basal") func tempBasalSegmentsDuringActiveSuspension() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspensionStart = start.addingTimeInterval(300)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspensionStart ... .distantFuture]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspensionStart, rate: 2.5)
        ])
    }

    /// Edge cases
    @Test("Suspend without resume terminates the temp basal") func suspendWithoutResume() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspensionStart = start.addingTimeInterval(300)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspensionStart ... .distantFuture]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspensionStart, rate: 2.5)
        ])
    }

    @Test("Multiple suspends before a single resume terminates at first suspension") func multipleSuspendsBeforeResume() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspend1 = start.addingTimeInterval(100)
        let suspend2 = start.addingTimeInterval(300)
        let resume = start.addingTimeInterval(400)
        let end = start.addingTimeInterval(900)

        let intervals = MainChartHelper.suspensionIntervals(
            events: [
                MainChartHelper.SuspensionEvent(date: suspend1, type: "suspend"),
                MainChartHelper.SuspensionEvent(date: suspend2, type: "suspend"),
                MainChartHelper.SuspensionEvent(date: resume, type: "resume")
            ],
            suspendType: "suspend",
            resumeType: "resume"
        )

        #expect(intervals == [suspend1 ... resume])

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: intervals
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspend1, rate: 2.5)
        ])
    }

    @Test("TBR starting during suspension produces no segment") func tempBasalStartsDuringSuspension() {
        let suspensionStart = Date(timeIntervalSince1970: 1000)
        let tbrStart = suspensionStart.addingTimeInterval(300)
        let resume = suspensionStart.addingTimeInterval(600)
        let end = suspensionStart.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: tbrStart, end: end, rate: 2.5)],
            suspensions: [suspensionStart ... resume]
        )

        #expect(segments.isEmpty)
    }

    @Test("TBR starting at suspension produces no segment") func tempBasalStartsAtSuspension() {
        let start = Date(timeIntervalSince1970: 1000)
        let resume = start.addingTimeInterval(600)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [start ... resume]
        )

        #expect(segments.isEmpty)
    }

    @Test("Suspend at scheduled basal boundary terminates TBR") func suspendAtBasalBoundary() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspend = start.addingTimeInterval(300)
        let resume = start.addingTimeInterval(600)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspend ... resume]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspend, rate: 2.5)
        ])
    }

    @Test("Resume without prior suspend is a no-op") func resumeWithoutSuspend() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(900)
        let event = MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)

        // No suspension intervals at all
        let segments = MainChartHelper.tempBasalSegments(events: [event], suspensions: [])

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: end, rate: 2.5)
        ])
    }

    @Test("Orphan resume yields no suspension interval") func orphanResumeYieldsNoInterval() {
        let resume = Date(timeIntervalSince1970: 1000)

        let intervals = MainChartHelper.suspensionIntervals(
            events: [MainChartHelper.SuspensionEvent(date: resume, type: "resume")],
            suspendType: "suspend",
            resumeType: "resume"
        )

        #expect(intervals.isEmpty)
    }

    @Test("Unmatched suspend stays open ended") func unmatchedSuspendStaysOpen() {
        let suspend = Date(timeIntervalSince1970: 1000)

        let intervals = MainChartHelper.suspensionIntervals(
            events: [MainChartHelper.SuspensionEvent(date: suspend, type: "suspend")],
            suspendType: "suspend",
            resumeType: "resume"
        )

        #expect(intervals == [suspend ... .distantFuture])
    }
}
