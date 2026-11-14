import Foundation
import Testing

@testable import Trio

@Suite("Nightscout Profile Import Tests") struct NightscoutProfileImportTests {
    /// A profile document as Loop uploads it: capitalised `Default`, mmol/L, `carbs_hr` and `delay` as strings,
    /// and Loop's own keys next to the store.
    static let loopDocument = """
    [{
      "_id": "6b0f2c9e-1111-4f5e-9a5b-0c1d2e3f4a5b",
      "defaultProfile": "Sport",
      "startDate": "2026-11-07T08:00:00.000Z",
      "mills": 1793952000000,
      "units": "mmol/L",
      "enteredBy": "Loop",
      "isAPNSProduction": false,
      "timeZone": "Europe/Stockholm",
      "created_at": "2026-11-07T08:00:01.000Z",
      "loopSettings": {
        "dosingEnabled": true,
        "overridePresets": [{"name": "Running", "symbol": "🏃", "duration": 3600, "targetRange": [8, 9], "insulinNeedsScaleFactor": 0.5}],
        "minimumBGGuard": 4.2,
        "maximumBasalRatePerHour": 3,
        "maximumBolus": 8,
        "dosingStrategy": "automaticBolus"
      },
      "profileEditLimits": {"units": "mmol/L", "maxBasal": 3, "basalRates": [0.05, 0.1], "maxSegments": 48, "segmentSeconds": 1800},
      "store": {
        "Default": {
          "dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mmol/L",
          "basal": [{"time": "00:00", "value": 0.85, "timeAsSeconds": 0}, {"time": "06:00", "value": 1.0, "timeAsSeconds": 21600}],
          "carbratio": [{"time": "00:00", "value": 10, "timeAsSeconds": 0}],
          "sens": [{"time": "00:00", "value": 2.8, "timeAsSeconds": 0}],
          "target_low": [{"time": "00:00", "value": 5.5, "timeAsSeconds": 0}],
          "target_high": [{"time": "00:00", "value": 6.1, "timeAsSeconds": 0}]
        },
        "Sport": {
          "dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mmol/L",
          "basal": [{"time": "00:00", "value": 0.5, "timeAsSeconds": 0}],
          "carbratio": [{"time": "00:00", "value": 12, "timeAsSeconds": 0}],
          "sens": [{"time": "00:00", "value": 3.5, "timeAsSeconds": 0}],
          "target_low": [{"time": "00:00", "value": 7, "timeAsSeconds": 0}],
          "target_high": [{"time": "00:00", "value": 8, "timeAsSeconds": 0}]
        },
        "School": {
          "dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mmol/L",
          "basal": [{"time": "00:00", "value": 0.7, "timeAsSeconds": 0}, {"time": "08:00", "value": 0.9, "timeAsSeconds": 28800}],
          "carbratio": [{"time": "00:00", "value": 9.5, "timeAsSeconds": 0}],
          "sens": [{"time": "00:00", "value": 3, "timeAsSeconds": 0}],
          "target_low": [{"time": "00:00", "value": 5.5, "timeAsSeconds": 0}],
          "target_high": [{"time": "00:00", "value": 6.5, "timeAsSeconds": 0}]
        },
        "Odd": {
          "dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-1", "units": "mmol/L",
          "basal": [{"time": "00:00", "value": 0.85, "timeAsSeconds": 0}],
          "carbratio": [{"time": "00:00", "value": 7.25, "timeAsSeconds": 0}],
          "sens": [{"time": "00:00", "value": 2.8, "timeAsSeconds": 0}],
          "target_low": [{"time": "00:00", "value": 5.5, "timeAsSeconds": 0}],
          "target_high": [{"time": "00:00", "value": 6.1, "timeAsSeconds": 0}]
        },
        "Broken": {"units": "mmol/L"}
      }
    }]
    """

    /// A profile document as Trio uploads it: lowercase `default`, mg/dL.
    static let trioDocument = """
    [{
      "_id": "64f0a1b2c3d4e5f601234567",
      "defaultProfile": "default",
      "startDate": "2026-11-07T08:00:00.000Z",
      "mills": 1793952000000,
      "units": "mg/dl",
      "enteredBy": "Trio",
      "created_at": "2026-11-07T08:00:01.000Z",
      "bundleIdentifier": "org.nightscout.TEAMID.trio",
      "remoteCommands": ["bolus", "switch_profile", "save_profile", "delete_profile"],
      "store": {
        "default": {
          "dia": 10, "carbs_hr": 26, "delay": 0, "timezone": "Europe/Stockholm", "units": "mg/dl",
          "basal": [{"time": "00:00", "value": 0.85, "timeAsSeconds": 0}],
          "carbratio": [{"time": "00:00", "value": 10, "timeAsSeconds": 0}],
          "sens": [{"time": "00:00", "value": 50, "timeAsSeconds": 0}],
          "target_low": [{"time": "00:00", "value": 100, "timeAsSeconds": 0}],
          "target_high": [{"time": "00:00", "value": 110, "timeAsSeconds": 0}]
        },
        "Weekend": {
          "dia": 10, "carbs_hr": 26, "delay": 0, "timezone": "Europe/Stockholm", "units": "mg/dl",
          "basal": [{"time": "00:00", "value": 0.75, "timeAsSeconds": 0}],
          "carbratio": [{"time": "00:00", "value": 11, "timeAsSeconds": 0}],
          "sens": [{"time": "00:00", "value": 55, "timeAsSeconds": 0}],
          "target_low": [{"time": "00:00", "value": 105, "timeAsSeconds": 0}],
          "target_high": [{"time": "00:00", "value": 105, "timeAsSeconds": 0}]
        }
      }
    }]
    """

    private func decode(_ json: String) throws -> FetchedNightscoutProfileStore {
        try #require(try JSONCoding.decoder.decode([FetchedNightscoutProfileStore].self, from: Data(json.utf8)).first)
    }

    @Test("An active profile whose values are out of range is reported") func activeOutOfRange() throws {
        // Saved by the Nightscout profile editor on an mmol/L site: the mg/dL values now claim mmol/L.
        let document = try decode("""
        [{"defaultProfile": "Unwell", "units": "mmol", "store": {
          "Unwell": {"units": "mmol",
            "basal": [{"time": "00:00", "value": 1.25, "timeAsSeconds": 0}],
            "carbratio": [{"time": "00:00", "value": 9, "timeAsSeconds": 0}],
            "sens": [{"time": "00:00", "value": 40, "timeAsSeconds": 0}],
            "target_low": [{"time": "00:00", "value": 90, "timeAsSeconds": 0}],
            "target_high": [{"time": "00:00", "value": 100, "timeAsSeconds": 0}]}}}]
        """)
        let profileImport = NightscoutProfileImport(store: document)
        #expect(profileImport.activeProblem != nil)
        #expect(NightscoutProfileImport(store: try decode(Self.loopDocument)).activeProblem == nil)
    }

    @Test("An import keeps at most the profile limit") func importLimit() throws {
        let entry = """
        {"units": "mg/dl", "basal": [{"time": "00:00", "value": 1.0, "timeAsSeconds": 0}],
         "carbratio": [{"time": "00:00", "value": 10, "timeAsSeconds": 0}], "sens": [{"time": "00:00", "value": 50, "timeAsSeconds": 0}],
         "target_low": [{"time": "00:00", "value": 100, "timeAsSeconds": 0}], "target_high": [{"time": "00:00", "value": 110, "timeAsSeconds": 0}]}
        """
        let names = (1 ... 24).map { String(format: "P%02d", $0) }
        let store = names.map { "\"\($0)\": \(entry)" }.joined(separator: ",")
        let profileImport = NightscoutProfileImport(store: try decode("""
        [{"defaultProfile": "P24", "units": "mg/dl", "store": {\(store)}}]
        """))
        #expect(profileImport.activeProfileName == "P24")
        #expect(profileImport.profiles.count == TherapyProfileLimits.maxProfiles - 2)
        #expect(profileImport.skipped.map(\.name) == ["P19", "P20", "P21", "P22", "P23"])
    }

    @Test("A Loop document imports every valid profile in mg/dL") func loopDocument() throws {
        let document = try decode(Self.loopDocument)
        #expect(document.activeStoreKey == "Sport")
        #expect(document.unreadableProfiles == ["Broken"])
        #expect(document.store["Sport"]?.units == "mmol/L")

        let imported = NightscoutProfileImport(store: document)
        #expect(imported.activeProfileName == "Sport")
        #expect(imported.profiles.map(\.name) == ["Default", "School"])

        let defaultProfile = try #require(imported.profiles.first)
        #expect(defaultProfile.isDefault)
        #expect(defaultProfile.storeKey == "default")
        #expect(defaultProfile.basal == [
            TherapyScheduleEntry(seconds: 0, value: TherapyProfileFixtures.decimal(0.85)),
            TherapyScheduleEntry(seconds: 21600, value: 1)
        ])
        #expect(defaultProfile.target == [TherapyTargetEntry(seconds: 0, low: 99, high: 99)])
        #expect(defaultProfile.sensitivity.map(\.value) == [50])

        let school = try #require(imported.profiles.last)
        #expect(school.basal.map(\.seconds) == [0, 28800])
        #expect(school.carbRatio.map(\.value) == [TherapyProfileFixtures.decimal(9.5)])

        #expect(imported.skipped.map(\.name) == ["Broken", "Odd"])
        #expect(imported.skipped.last?.reason.contains(TherapyProfileFixtures.decimal(7.25).formatted()) == true)
    }

    @Test("A Trio document maps default to the Default profile") func trioDocument() throws {
        let document = try decode(Self.trioDocument)
        #expect(document.activeStoreKey == "default")
        let imported = NightscoutProfileImport(store: document)
        #expect(imported.activeProfileName == "Default")
        #expect(imported.profiles.map(\.name) == ["Weekend"])
        #expect(imported.profiles.first?.sensitivity.map(\.value) == [55])
        #expect(imported.profiles.first?.target == [TherapyTargetEntry(seconds: 0, low: 105, high: 105)])
        #expect(imported.skipped.isEmpty)
    }

    @Test("Glucose values in mg/dL are rounded to whole mg/dL") func fractionalMgdl() throws {
        let json = Self.trioDocument
            .replacingOccurrences(of: "\"value\": 55,", with: "\"value\": 50.44,")
            .replacingOccurrences(of: "\"value\": 105,", with: "\"value\": 100.887,")
        let imported = NightscoutProfileImport(store: try decode(json))
        #expect(imported.skipped.isEmpty)
        #expect(imported.profiles.first?.sensitivity.map(\.value) == [50])
        #expect(imported.profiles.first?.target == [TherapyTargetEntry(seconds: 0, low: 101, high: 101)])
    }

    @Test("defaultProfile naming no entry falls back to default") func missingActive() throws {
        let json = Self.trioDocument.replacingOccurrences(
            of: "\"defaultProfile\": \"default\"",
            with: "\"defaultProfile\": \"Gone\""
        )
        let imported = NightscoutProfileImport(store: try decode(json))
        #expect(imported.activeProfileName == "Default")
        #expect(imported.profiles.map(\.name) == ["Weekend"])
    }

    @Test("An active profile whose name Trio does not accept is imported as Default") func invalidActiveName() throws {
        let json = Self.loopDocument
            .replacingOccurrences(of: "\"defaultProfile\": \"Sport\"", with: "\"defaultProfile\": \"Mon.Fri\"")
            .replacingOccurrences(of: "\"Sport\": {", with: "\"Mon.Fri\": {")
        let document = try decode(json)
        #expect(document.activeStoreKey == "Mon.Fri")

        let imported = NightscoutProfileImport(store: document)
        #expect(imported.activeProfileName == "Default")
        #expect(imported.profiles.map(\.name) == ["School"])
        #expect(imported.skipped.map(\.name) == ["Broken", "Mon.Fri", "Odd", "Default"])
        #expect(imported.skipped.first { $0.name == "Mon.Fri" }?.reason.contains("Default") == true)
    }

    @Test("A second entry that maps to Default is skipped") func duplicateDefault() throws {
        let json = Self.trioDocument.replacingOccurrences(of: "\"Weekend\"", with: "\"Default\"")
        let imported = NightscoutProfileImport(store: try decode(json))
        #expect(imported.activeProfileName == "Default")
        #expect(imported.profiles.isEmpty)
        #expect(imported.skipped.map(\.name) == ["Default"])
    }

    @Test("Imported profiles are stored with the document's active profile") func replaceProfiles() async throws {
        let live = TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)], carbratio: [(0, 12)])
        let context = try await TherapyProfileTestContext.make(live: live)
        let imported = NightscoutProfileImport(store: try decode(Self.loopDocument))

        try await context.manager.replaceProfiles(
            imported.profiles,
            activeProfileName: imported.activeProfileName,
            scheduledSwitches: imported.scheduledSwitches
        )

        #expect(context.manager.activeProfileName == "Sport")
        #expect(context.manager.profiles().map(\.name) == ["Default", "School", "Sport"])
        #expect(context.manager.activeProfile().hasSameValues(as: live))
        #expect(context.manager.profile(named: "default")?.basal.map(\.value) == [TherapyProfileFixtures.decimal(0.85), 1])
        #expect(context.liveBasal == [TherapyProfileFixtures.decimal(0.5)])
        #expect(context.recorder.events == [.profilesChanged])
    }

    @Test("Without a Default entry, Default takes the live settings") func replaceProfilesWithoutDefault() async throws {
        let live = TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)])
        let context = try await TherapyProfileTestContext.make(live: live)

        try await context.manager.replaceProfiles([], activeProfileName: "Sport", scheduledSwitches: [])

        #expect(context.manager.profiles().map(\.name) == ["Default", "Sport"])
        #expect(context.manager.profile(named: "Default")?.hasSameValues(as: live) == true)
    }

    @Test("Scheduled switches to imported profiles are imported, the others are listed") func scheduledSwitches() async throws {
        let json = Self.trioDocument.replacingOccurrences(of: "\"store\": {", with: """
        "scheduledSwitches": [
          {"id": "w", "profile": "Weekend", "weekday": 7, "time": 25200, "paused": true},
          {"id": "s", "profile": "default", "weekday": 2, "time": 21600},
          {"id": "g", "profile": "Gone", "weekday": 4, "time": 0},
          {"id": "o", "profile": "Weekend", "date": "2026-11-14", "time": 28800}
        ],
        "store": {
        """)
        let document = try decode(json)
        #expect(document.unreadableScheduledSwitches == 1)

        let imported = NightscoutProfileImport(store: document)
        #expect(imported.scheduledSwitches == [
            ScheduledProfileSwitch(id: "w", profileName: "Weekend", weekday: 7, time: 25200, paused: true),
            ScheduledProfileSwitch(id: "s", profileName: "Default", weekday: 2, time: 21600)
        ])
        #expect(imported.skipped.count == 2)
        #expect(imported.skipped.contains { $0.name.hasPrefix("Gone") })

        let context = try await TherapyProfileTestContext.make()
        try await context.manager.replaceProfiles(
            imported.profiles,
            activeProfileName: imported.activeProfileName,
            scheduledSwitches: imported.scheduledSwitches
        )
        #expect(context.manager.scheduledSwitches().map(\.id) == ["s", "w"])
        #expect(try context.profileStorage.fetchProfiles().scheduledSwitchesSettledAt == context.recorder.now)
    }
}
