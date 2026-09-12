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

@Suite("Dosing Mode Reporting") struct DosingModeReportingTests {
    @Test("Followers receive the raw value, which does not shift with locale") func rawValuesAreStable() {
        #expect(DosingMode.closed.rawValue == "closed")
        #expect(DosingMode.open.rawValue == "open")
        #expect(DosingMode.lowGlucoseSuspend.rawValue == "lowGlucoseSuspend")
        #expect(DosingMode.basalTesting.rawValue == "basalTesting")
    }

    @Test("Devicestatus carries the mode and drops enacted only in open loop") func deviceStatusPayload() throws {
        func payload(for mode: DosingMode) throws -> [String: Any] {
            let status = OpenAPSStatus(
                iob: nil,
                suggested: nil,
                enacted: nil,
                version: "1.0",
                recommendedBolus: nil,
                dosingMode: mode.rawValue
            )
            let data = try JSONEncoder().encode(status)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        for mode in DosingMode.allCases {
            let json = try payload(for: mode)
            #expect(json["dosingMode"] as? String == mode.rawValue)
        }
    }
}
