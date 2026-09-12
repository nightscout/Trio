import Foundation
import Testing
@testable import Trio

@Suite("Dosing Mode Migration") struct DosingModeMigrationTests {
    private func decode(_ json: String) throws -> TrioSettings {
        try JSONDecoder().decode(TrioSettings.self, from: Data(json.utf8))
    }

    @Test("Legacy closedLoop true migrates to closed") func legacyClosedLoopTrue() throws {
        #expect(try decode(#"{"closedLoop": true}"#).dosingMode == .closed)
    }

    @Test("Legacy closedLoop false migrates to open") func legacyClosedLoopFalse() throws {
        #expect(try decode(#"{"closedLoop": false}"#).dosingMode == .open)
    }

    @Test("Stored dosingMode wins over a stale legacy key") func dosingModeWinsOverLegacy() throws {
        let settings = try decode(#"{"dosingMode": "lowGlucoseSuspend", "closedLoop": true}"#)
        #expect(settings.dosingMode == .lowGlucoseSuspend)
    }

    @Test("Every mode round-trips") func everyModeRoundTrips() throws {
        for mode in DosingMode.allCases {
            let encoded = try JSONEncoder().encode(TrioSettings(dosingMode: mode))
            let decoded = try JSONDecoder().decode(TrioSettings.self, from: encoded)
            #expect(decoded.dosingMode == mode)
        }
    }

    @Test("Unknown or missing values fall back to open") func unknownFallsBackToOpen() throws {
        #expect(try decode(#"{"dosingMode": "teleportation"}"#).dosingMode == .open)
        #expect(try decode("{}").dosingMode == .open)
    }

    @Test("Automation level reflects what each mode may do") func automationLevels() {
        #expect(DosingMode.open.automation == .off)
        #expect(DosingMode.basalTesting.automation == .hypoSuspendOnly)
        #expect(DosingMode.lowGlucoseSuspend.automation == .reductionsOnly)
        #expect(DosingMode.closed.automation == .full)
    }

    @Test("Only closed loop may dose above scheduled basal") func onlyClosedLoopCorrects() {
        for mode in DosingMode.allCases where mode != .closed {
            #expect(mode.automation != .full)
        }
    }

    @Test("Every mode is selectable now that the clamps exist") func userSelectableModes() {
        #expect(DosingMode.userSelectable == DosingMode.allCases)
    }

    @Test("Bundled defaults ship in open loop") func bundledDefaultIsOpen() throws {
        let defaults = OpenAPS.defaults(for: OpenAPS.Trio.settings)
        let settings = try #require(TrioSettings(from: defaults))
        #expect(settings.dosingMode == .open)
    }
}
