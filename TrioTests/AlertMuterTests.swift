import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: AlertMuter") struct AlertMuterTests {
    @Test("Default state is unmuted") func defaultUnmuted() {
        let muter = AlertMuter()
        #expect(!muter.shouldMute(at: Date()))
        #expect(muter.endsAt == nil)
    }

    @Test("mute(for:) covers the start through end-exclusive boundary") func muteWindowMath() {
        let muter = AlertMuter()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        muter.mute(for: 600, from: start)

        #expect(muter.shouldMute(at: start)) // inclusive start
        #expect(muter.shouldMute(at: start.addingTimeInterval(1)))
        #expect(muter.shouldMute(at: start.addingTimeInterval(599)))
        #expect(!muter.shouldMute(at: start.addingTimeInterval(600))) // exclusive end
        #expect(!muter.shouldMute(at: start.addingTimeInterval(601)))
        #expect(!muter.shouldMute(at: start.addingTimeInterval(-1)))
        #expect(muter.endsAt == start.addingTimeInterval(600))
    }

    @Test("unmute() clears the window") func unmuteClears() {
        let muter = AlertMuter()
        let start = Date()
        muter.mute(for: 3600, from: start)
        #expect(muter.shouldMute(at: start.addingTimeInterval(60)))

        muter.unmute()
        #expect(!muter.shouldMute(at: start.addingTimeInterval(60)))
        #expect(muter.endsAt == nil)
    }

    @Test("mute(for: 0) creates a zero-length window — never mutes") func zeroDurationNoOp() {
        let muter = AlertMuter()
        let start = Date()
        muter.mute(for: 0, from: start)
        #expect(!muter.shouldMute(at: start))
        #expect(!muter.shouldMute(at: start.addingTimeInterval(1)))
    }

    @Test("Re-muting replaces the previous window rather than stacking") func reMuteReplaces() {
        let muter = AlertMuter()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        muter.mute(for: 600, from: first)

        let second = first.addingTimeInterval(120)
        muter.mute(for: 60, from: second)

        // Second window ends at first+180, not first+600.
        #expect(muter.shouldMute(at: second.addingTimeInterval(30)))
        #expect(!muter.shouldMute(at: second.addingTimeInterval(60)))
        #expect(!muter.shouldMute(at: first.addingTimeInterval(300)))
        #expect(muter.endsAt == second.addingTimeInterval(60))
    }
}
