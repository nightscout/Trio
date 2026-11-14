import Foundation
import Testing
@testable import Trio

@Suite("Therapy Profile Nightscout Tests") struct TherapyProfileNightscoutTests {
    private func store(_ profiles: [TrioTherapyProfile], units: GlucoseUnits) -> [String: ScheduledNightscoutProfile] {
        ScheduledNightscoutProfile.store(profiles: profiles, units: units, dia: 6, min5mCarbimpact: 8, timezone: "UTC")
    }

    @Test("The store holds default and the named profiles") func storeEntries() throws {
        let store = store(
            [TherapyProfileFixtures.profile("Default"), TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)])],
            units: .mmolL
        )
        #expect(Set(store.keys) == ["default", "Sport"])
        let sport = try #require(store["Sport"])
        #expect(sport.units == "mmol")
        #expect(sport.sens.first?.value == TherapyProfileFixtures.decimal(2.8))
        #expect(sport.target_low.first?.value == TherapyProfileFixtures.decimal(5.6))
        #expect(sport.basal.first?.value == TherapyProfileFixtures.decimal(0.5))
        #expect(sport.basal.first?.time == "00:00")
        #expect(sport.basal.first?.timeAsSeconds == 0)
        #expect(store["default"]?.basal.last?.time == "06:00")
    }

    @Test("A store entry has the profile's fingerprint") func storeFingerprint() throws {
        let profile = TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)])
        let entry = try #require(store([profile], units: .mmolL)["Sport"])
        func pairs(_ values: [NightscoutTimevalue]) -> [(Int, Decimal)] { values.map { ($0.timeAsSeconds ?? 0, $0.value) } }
        let canonical = TrioTherapyProfile.fingerprintCanonicalString(
            basal: pairs(entry.basal),
            carbratio: pairs(entry.carbratio),
            sens: pairs(entry.sens),
            targetLow: pairs(entry.target_low),
            targetHigh: pairs(entry.target_high)
        )
        #expect(profile.matchesFingerprint(TrioTherapyProfile.fingerprint(of: canonical)))
    }

    @Test("The profile switch treatment has the contract fields") func switchTreatment() throws {
        let treatment = NightscoutTreatment(
            duration: 0,
            eventType: .nsProfileSwitch,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            enteredBy: NightscoutTreatment.local,
            targetTop: nil,
            targetBottom: nil,
            profile: "Sport"
        )
        let object = try #require(try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(treatment)) as? [String: Any])
        #expect(object["eventType"] as? String == "Profile Switch")
        #expect(object["profile"] as? String == "Sport")
        #expect(object["enteredBy"] as? String == "Trio")
        #expect(object["duration"] as? Int == 0)
        #expect(Set(object.keys) == ["eventType", "profile", "enteredBy", "duration", "created_at"])
    }

    @Test("A scheduled or remote switch carries a note, a local one none") func switchTreatmentNotes() throws {
        #expect(TherapyProfileSwitch.Trigger.scheduled.nightscoutNote == "Scheduled")
        #expect(TherapyProfileSwitch.Trigger.remote.nightscoutNote == "Remote")
        #expect(TherapyProfileSwitch.Trigger.local.nightscoutNote == nil)
        let treatment = NightscoutTreatment(
            duration: 0,
            eventType: .nsProfileSwitch,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            enteredBy: NightscoutTreatment.local,
            notes: TherapyProfileSwitch.Trigger.scheduled.nightscoutNote,
            targetTop: nil,
            targetBottom: nil,
            profile: "Weekend"
        )
        let object = try #require(try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(treatment)) as? [String: Any])
        #expect(object["notes"] as? String == "Scheduled")
    }

    @Test("Scheduled switches round-trip in the compact form, paused only when set") func compactScheduledSwitches() throws {
        let entries = [
            ScheduledProfileSwitch(id: "5A3D9D6E-1C7F-4A52-9C1D-2B3F9E0F7A11", profileName: "Weekend", weekday: 7, time: 25200),
            ScheduledProfileSwitch(
                id: "B0E6C2F4-8D1B-4F0E-A6A7-3C2E5D9B1F02",
                profileName: "default",
                weekday: 2,
                time: 21600,
                paused: true
            )
        ]
        let data = try JSONEncoder().encode(entries)
        let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(objects[0]["paused"] == nil)
        #expect(objects[1]["paused"] as? Bool == true)
        #expect(Set(objects[0].keys) == ["id", "profile", "weekday", "time"])
        #expect(try JSONDecoder().decode([ScheduledProfileSwitch].self, from: data) == entries)

        let oneOff = #"{"id":"x","profile":"Sick","date":"2026-11-14","time":28800}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScheduledProfileSwitch.self, from: Data(oneOff.utf8))
        }
    }

    @Test("The profile document carries the scheduled switches and their fingerprint") func documentScheduledSwitches() throws {
        let entries = [
            ScheduledProfileSwitch(id: "w", profileName: "Weekend", weekday: 7, time: 25200),
            ScheduledProfileSwitch(id: "s", profileName: "Default", weekday: 2, time: 21600)
        ].withStoreKeys
        let document = NightscoutProfileStore(
            defaultProfile: "default",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            mills: 1_800_000_000_000,
            units: "mg/dl",
            enteredBy: NightscoutTreatment.local,
            store: store([TherapyProfileFixtures.profile("Default")], units: .mgdL),
            bundleIdentifier: "",
            deviceToken: "",
            isAPNSProduction: false,
            overridePresets: nil,
            teamID: "",
            expirationDate: nil,
            remoteCommands: TrioRemoteControl.CommandType.supported.map(\.rawValue),
            scheduledSwitches: entries,
            scheduledSwitchesFingerprint: entries.fingerprint
        )
        let object = try #require(try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(document)) as? [String: Any])
        let uploaded = try #require(object["scheduledSwitches"] as? [[String: Any]])
        #expect(uploaded.map { $0["profile"] as? String } == ["Weekend", "default"])
        #expect(object["scheduledSwitchesFingerprint"] as? String == entries.fingerprint)
        #expect(
            [
                ScheduledProfileSwitch(id: "s", profileName: "Default", weekday: 2, time: 21600),
                ScheduledProfileSwitch(id: "w", profileName: "Weekend", weekday: 7, time: 25200)
            ]
            .matchesFingerprint(entries.fingerprint)
        )
    }

    @Test("A switch is recorded with what triggered it") func switchTrigger() async throws {
        let context = try await TherapyProfileTestContext.make()
        let sport = TherapyProfileFixtures.profile("Sport", basal: [(0, 0.5)])
        try await context.manager.save(sport, originalName: nil, baseFingerprint: nil)
        let start = context.recorder.now
        try await context.manager.activate("Sport", expectedFingerprint: nil)
        context.recorder.now = start.addingTimeInterval(60)
        try await context.manager.activate("Default", expectedFingerprint: nil, trigger: .remote)
        let weekday = TherapyProfileTestRecorder.calendar.component(.weekday, from: start)
        let minute = TherapyProfileTestRecorder.calendar.dateComponents([.hour, .minute], from: start)
        try await context.manager.saveScheduledSwitches(
            [ScheduledProfileSwitch(
                profileName: "Sport",
                weekday: weekday,
                time: ((minute.hour ?? 0) * 60 + (minute.minute ?? 0) + 2) * 60
            )],
            baseFingerprint: nil
        )
        context.recorder.now = start.addingTimeInterval(180)
        await context.manager.runDueScheduledSwitch()
        #expect(try context.profileStorage.profileSwitchesNotYetUploaded().map(\.trigger) == [.local, .remote, .scheduled])
    }
}
