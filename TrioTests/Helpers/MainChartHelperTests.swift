import Foundation
import Testing
@testable import Trio

@Suite("Main Chart Helper Tests") struct MainChartHelperTests {
    @Test("Suspension splits a temp basal and preserves delivery after resume") func tempBasalSegmentsAroundSuspension() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspensionStart = start.addingTimeInterval(300)
        let resume = start.addingTimeInterval(600)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspensionStart ... resume]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspensionStart, rate: 2.5),
            MainChartHelper.TempBasalSegment(start: suspensionStart, end: resume, rate: 0),
            MainChartHelper.TempBasalSegment(start: resume, end: end, rate: 2.5),
        ])
    }

    @Test("Recalculation after resume restores the full temp basal") func tempBasalSegmentsAfterResume() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(900)
        let event = MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)

        let segments = MainChartHelper.tempBasalSegments(events: [event], suspensions: [])

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: end, rate: 2.5),
        ])
    }

    @Test("Active suspension keeps the remaining temp basal at zero") func tempBasalSegmentsDuringActiveSuspension() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspensionStart = start.addingTimeInterval(300)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspensionStart ... .distantFuture]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspensionStart, rate: 2.5),
            MainChartHelper.TempBasalSegment(start: suspensionStart, end: end, rate: 0),
        ])
    }

    /// Edge cases
    @Test("Suspend without resume (time cutoff) stops delivery until time limit") func suspendWithoutResume() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspensionStart = start.addingTimeInterval(300)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspensionStart ... .distantFuture]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspensionStart, rate: 2.5),
            MainChartHelper.TempBasalSegment(start: suspensionStart, end: end, rate: 0),
        ])
    }

    @Test("Multiple suspends before a single resume") func multipleSuspendsBeforeResume() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspend1 = start.addingTimeInterval(100)
        let resume1 = start.addingTimeInterval(200)
        let suspend2 = start.addingTimeInterval(300)
        let resume2 = start.addingTimeInterval(400)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspend1 ... resume1, suspend2 ... resume2]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspend1, rate: 2.5),
            MainChartHelper.TempBasalSegment(start: suspend1, end: resume1, rate: 0),
            MainChartHelper.TempBasalSegment(start: resume1, end: suspend2, rate: 2.5),
            MainChartHelper.TempBasalSegment(start: suspend2, end: resume2, rate: 0),
            MainChartHelper.TempBasalSegment(start: resume2, end: end, rate: 2.5),
        ])
    }

    @Test("Suspend that overlaps scheduled basal boundary") func suspendAtBasalBoundary() {
        let start = Date(timeIntervalSince1970: 1000)
        let suspend = start.addingTimeInterval(300)
        let resume = start.addingTimeInterval(600)
        let end = start.addingTimeInterval(900)

        let segments = MainChartHelper.tempBasalSegments(
            events: [MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)],
            suspensions: [suspend ... resume]
        )

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: suspend, rate: 2.5),
            MainChartHelper.TempBasalSegment(start: suspend, end: resume, rate: 0),
            MainChartHelper.TempBasalSegment(start: resume, end: end, rate: 2.5),
        ])
    }

    @Test("Resume without prior suspend is a no-op") func resumeWithoutSuspend() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(900)
        let event = MainChartHelper.TempBasalEvent(start: start, end: end, rate: 2.5)

        // No suspension intervals at all
        let segments = MainChartHelper.tempBasalSegments(events: [event], suspensions: [])

        #expect(segments == [
            MainChartHelper.TempBasalSegment(start: start, end: end, rate: 2.5),
        ])
    }
}
