import CoreData
import Foundation
import LoopKit
import Swinject
import Testing

@testable import Trio

@Suite("Remote Treatment Guard Tests") struct RemoteTreatmentGuardTests {
    private typealias Guard = RemoteTreatmentGuard
    private typealias Candidate = RemoteTreatmentGuard.Candidate

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ value: Double) -> Date {
        now.addingTimeInterval(value * 60)
    }

    /// A Nightscout `_id` inserted at `date`.
    private func objectId(at date: Date, suffix: String = "0000000000000000") -> String {
        String(format: "%08x", UInt32(date.timeIntervalSince1970)) + suffix
    }

    private func context(
        sentAt sendTime: Date,
        knownThrough marker: String? = nil,
        uploadEnabled: Bool = true,
        markerRuleStart: Date? = Date(timeIntervalSince1970: 1_799_900_000)
    ) -> Guard.Context {
        Guard.Context(
            sendTime: sendTime,
            now: now,
            knownThroughId: marker,
            isNightscoutUploadEnabled: uploadEnabled,
            markerRuleStart: markerRuleStart
        )
    }

    private func bolus(_ units: Decimal, at date: Date, uploadedAt uploadDate: Date? = nil) -> Candidate {
        Candidate(date: date, amount: units, nightscoutId: uploadDate.map { objectId(at: $0) })
    }

    // MARK: - Object id

    @Test("Object id time is the first 8 hex characters in seconds") func testObjectIdDate() {
        let id = NightscoutObjectId("65a1b2c3d4e5f60718293a4b")
        #expect(id?.date == Date(timeIntervalSince1970: TimeInterval(0x65A1_B2C3)))
    }

    @Test("Invalid object ids are rejected") func testInvalidObjectIds() {
        #expect(NightscoutObjectId("NA") == nil)
        #expect(NightscoutObjectId(nil) == nil)
        #expect(NightscoutObjectId("65a1b2c3d4e5f60718293a4") == nil)
        #expect(NightscoutObjectId("65a1b2c3d4e5f60718293a4g") == nil)
        #expect(NightscoutObjectId("65A1B2C3D4E5F60718293A4B") != nil)
    }

    // MARK: - Bolus

    @Test("Unknown insulin below 20% of the request is allowed") func testUnknownInsulinBelowThreshold() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let boluses = [bolus(0.25, at: minutes(-2), uploadedAt: minutes(-2))]

        #expect(Guard.evaluateBolus(requested: 2.5, boluses: boluses, context: ctx) == .allowed)
    }

    @Test("Unknown insulin at or above 20% of the request is rejected") func testUnknownInsulinAboveThreshold() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let boluses = [bolus(0.25, at: minutes(-3), uploadedAt: minutes(-3)), bolus(0.25, at: minutes(-1))]

        let decision = Guard.evaluateBolus(requested: 2.5, boluses: boluses, context: ctx)
        #expect(decision == .unknownInsulin(units: 0.5, notUploadedOnly: false))
        #expect(
            decision.rejectionMessage ==
                "Command rejected: 0.5 U of insulin was delivered after the command was sent (or after the newest treatment you had seen)."
        )
    }

    @Test("Insulin the sender had seen is allowed") func testKnownInsulinAllowed() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-20)))
        let boluses = [bolus(3, at: minutes(-30), uploadedAt: minutes(-29))]

        #expect(Guard.evaluateBolus(requested: 2, boluses: boluses, context: ctx) == .allowed)
    }

    @Test("An in-progress bolus counts with its programmed amount") func testInProgressBolus() {
        #expect(Guard.bolusUnits(delivered: 0.5, programmed: 3, isInProgress: true) == 3)
        #expect(Guard.bolusUnits(delivered: 2.5, programmed: 3, isInProgress: false) == 2.5)

        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let inProgress = Candidate(
            date: minutes(-1),
            amount: Guard.bolusUnits(delivered: 0.25, programmed: 2, isInProgress: true),
            nightscoutId: nil
        )
        #expect(
            Guard
                .evaluateBolus(requested: 2, boluses: [inProgress], context: ctx) ==
                .unknownInsulin(units: 2, notUploadedOnly: false)
        )
    }

    @Test("A bolus without a cached _id is unknown under a marker") func testMissingObjectId() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let notUploaded = Candidate(date: minutes(-60), amount: 1, nightscoutId: nil)

        let decision = Guard.evaluateBolus(requested: 2, boluses: [notUploaded], context: ctx)
        #expect(decision == .unknownInsulin(units: 1, notUploadedOnly: true))
        #expect(decision.rejectionMessage == "Command rejected: 1 U of insulin has not been uploaded to Nightscout yet.")
    }

    @Test("An \"NA\" _id counts as missing") func testNAObjectId() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let candidate = Candidate(date: minutes(-60), amount: 1, nightscoutId: "NA")

        #expect(
            Guard.evaluateBolus(requested: 2, boluses: [candidate], context: ctx) ==
                .unknownInsulin(units: 1, notUploadedOnly: true)
        )
    }

    @Test("An invalid marker is treated as absent") func testInvalidMarker() {
        let ctx = context(sentAt: minutes(-5), knownThrough: "not-an-object-id")
        let notUploaded = Candidate(date: minutes(-60), amount: 1, nightscoutId: nil)

        #expect(ctx.knownThrough == nil)
        #expect(Guard.evaluateBolus(requested: 2, boluses: [notUploaded], context: ctx) == .allowed)
    }

    @Test("Without a marker only the send-time rule applies") func testNoMarkerSendTimeRule() {
        let ctx = context(sentAt: minutes(-5))
        let before = Candidate(date: minutes(-6), amount: 3, nightscoutId: nil)
        let after = Candidate(date: minutes(-4), amount: 0.5, nightscoutId: nil)

        #expect(Guard.evaluateBolus(requested: 2, boluses: [before], context: ctx) == .allowed)
        #expect(
            Guard.evaluateBolus(requested: 2, boluses: [before, after], context: ctx) ==
                .unknownInsulin(units: 0.5, notUploadedOnly: false)
        )
    }

    @Test("With upload disabled the marker is ignored") func testUploadDisabled() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)), uploadEnabled: false)
        let notUploaded = Candidate(date: minutes(-60), amount: 1, nightscoutId: nil)

        #expect(Guard.evaluateBolus(requested: 2, boluses: [notUploaded], context: ctx) == .allowed)
    }

    @Test("A marker older than the send time rejects insulin uploaded in between") func testMarkerOlderThanSendTime() {
        // The sender's last fetch saw treatments through -15 min; it sent at -5 min.
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-15)))
        let boluses = [bolus(1, at: minutes(-10), uploadedAt: minutes(-9))]

        #expect(
            Guard.evaluateBolus(requested: 2, boluses: boluses, context: ctx) ==
                .unknownInsulin(units: 1, notUploadedOnly: false)
        )
    }

    @Test("Two caregivers: the second command is rejected after the first bolus") func testTwoCaregivers() {
        // Caregiver A's 2 U bolus was enacted at -4 min and uploaded at -3 min.
        let boluses = [bolus(2, at: minutes(-4), uploadedAt: minutes(-3))]

        // Caregiver B fetched before A's bolus reached Nightscout and sent at -2 min.
        let callerB = context(sentAt: minutes(-2), knownThrough: objectId(at: minutes(-8)))
        #expect(
            Guard.evaluateBolus(requested: 2, boluses: boluses, context: callerB) ==
                .unknownInsulin(units: 2, notUploadedOnly: false)
        )

        // Caregiver B after a fresh fetch that includes A's bolus.
        let refreshedB = context(sentAt: minutes(-1), knownThrough: objectId(at: minutes(-3)))
        #expect(Guard.evaluateBolus(requested: 2, boluses: boluses, context: refreshedB) == .allowed)
    }

    @Test("Treatments older than the lookback are ignored") func testLookback() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let old = Candidate(date: minutes(-6 * 60 - 1), amount: 5, nightscoutId: nil)

        #expect(Guard.evaluateBolus(requested: 2, boluses: [old], context: ctx) == .allowed)
    }

    // MARK: - Carbs

    @Test("A backdated carb entry uploaded after the marker is rejected") func testBackdatedCarbAfterMarker() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let backdated = Candidate(date: minutes(-45), amount: 20, nightscoutId: objectId(at: minutes(-2)))

        let decision = Guard.evaluateCarbs(carbEntries: [backdated], context: ctx)
        #expect(decision == .unknownCarbs(count: 1, grams: 20))
        #expect(decision.rejectionMessage == "Command rejected: a carb entry of 20 g was recorded that you had not seen.")
    }

    @Test("A backdated carb entry is allowed without a marker") func testBackdatedCarbWithoutMarker() {
        let ctx = context(sentAt: minutes(-5))
        let backdated = Candidate(date: minutes(-45), amount: 20, nightscoutId: nil)

        #expect(Guard.evaluateCarbs(carbEntries: [backdated], context: ctx) == .allowed)
    }

    @Test("A known future-dated carb entry is allowed") func testFutureCarbKnown() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let future = Candidate(date: minutes(60), amount: 15, nightscoutId: objectId(at: minutes(-10)))

        #expect(Guard.evaluateCarbs(carbEntries: [future], context: ctx) == .allowed)
    }

    @Test("An unknown future-dated carb entry is rejected") func testFutureCarbUnknown() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let uploadedLater = Candidate(date: minutes(60), amount: 15, nightscoutId: objectId(at: minutes(-1)))
        let notUploaded = Candidate(date: minutes(90), amount: 10, nightscoutId: nil)

        #expect(Guard.evaluateCarbs(carbEntries: [uploadedLater], context: ctx) == .unknownCarbs(count: 1, grams: 15))
        #expect(
            Guard.evaluateCarbs(carbEntries: [uploadedLater, notUploaded], context: ctx) ==
                .unknownCarbs(count: 2, grams: 25)
        )
    }

    @Test("A carb entry dated after the send time is rejected without a marker") func testCarbAfterSendTime() {
        let ctx = context(sentAt: minutes(-5))
        let entry = Candidate(date: minutes(-1), amount: 30, nightscoutId: nil)

        #expect(Guard.evaluateCarbs(carbEntries: [entry], context: ctx) == .unknownCarbs(count: 1, grams: 30))
    }

    // MARK: - Object id cache

    @Test("Upload responses map echoed ids to _ids and skip incomplete objects") func testUploadResponseMappings() {
        let response = """
        [{"_id":"65a1b2c3d4e5f60718293a4b","id":"AAA","insulin":1},
         {"id":"BBB","insulin":2},
         {"_id":"65a1b2c3d4e5f60718293a4c","carbs":10}]
        """
        let mappings = NightscoutObjectIdCache.mappings(fromUploadResponse: Data(response.utf8), localIds: ["AAA", "BBB"])

        #expect(mappings.count == 1)
        #expect(mappings.first?.localId == "AAA")
        #expect(mappings.first?.objectId == "65a1b2c3d4e5f60718293a4b")
        #expect(NightscoutObjectIdCache.mappings(fromUploadResponse: Data(response.utf8), localIds: ["BBB"]).isEmpty)
        #expect(NightscoutObjectIdCache.mappings(fromUploadResponse: Data("{}".utf8), localIds: ["AAA"]).isEmpty)
    }

    @Test("Cache keeps the newest _id per key and purges after retention") func testCacheRecordAndPurge() {
        var cache = NightscoutObjectIdCache()
        let older = objectId(at: minutes(-10))
        let newer = objectId(at: minutes(-5))

        cache.record(localId: "fpu-Family", objectId: newer, at: now)
        cache.record(localId: "FPU-family", objectId: older, at: now)
        cache.record(localId: "bolus", objectId: "NA", at: now)

        #expect(cache.objectId(forLocalId: "fpu-family") == newer)
        #expect(cache.objectId(forLocalId: "bolus") == nil)

        cache.purge(now: now.addingTimeInterval(NightscoutObjectIdCache.retention + 1))
        #expect(cache.objectId(forLocalId: "fpu-family") == nil)
    }

    // MARK: - Marker plausibility and recording start

    @Test("The marker rule covers only candidates created after recording started") func testFirstMappingCutoff() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)), markerRuleStart: minutes(-30))
        let beforeRecording = Candidate(date: minutes(-60), amount: 3, nightscoutId: nil)
        let afterRecording = Candidate(date: minutes(-20), amount: 1, nightscoutId: nil)

        #expect(Guard.evaluateBolus(requested: 2, boluses: [beforeRecording], context: ctx) == .allowed)
        #expect(
            Guard.evaluateBolus(requested: 2, boluses: [beforeRecording, afterRecording], context: ctx) ==
                .unknownInsulin(units: 1, notUploadedOnly: true)
        )

        let neverRecorded = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)), markerRuleStart: nil)
        #expect(Guard.evaluateBolus(requested: 2, boluses: [afterRecording], context: neverRecorded) == .allowed)
    }

    @Test("A marker more than 5 minutes ahead of now is invalid") func testFarFutureMarker() {
        let farFuture = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(6)))
        let nearFuture = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(4)))
        let notUploaded = Candidate(date: minutes(-60), amount: 1, nightscoutId: nil)

        #expect(farFuture.knownThrough == nil)
        #expect(nearFuture.knownThrough != nil)
        #expect(Guard.evaluateBolus(requested: 2, boluses: [notUploaded], context: farFuture) == .allowed)
    }

    // MARK: - In-flight boluses

    @Test("The pump's bolus in progress counts until it is stored") func testPumpBolusInProgress() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let pump = Guard.InFlightBolus(date: minutes(-1), units: 3, syncIdentifier: "dose-1")

        let candidates = Guard.bolusCandidates(stored: [], pumpBolusInProgress: pump, pendingRemoteBolus: nil, now: now)
        #expect(candidates == [Candidate(date: minutes(-1), amount: 3, nightscoutId: nil)])
        #expect(
            Guard.evaluateBolus(requested: 2, boluses: candidates, context: ctx) ==
                .unknownInsulin(units: 3, notUploadedOnly: false)
        )

        let stored = Guard.StoredBolus(
            candidate: Candidate(date: minutes(-1), amount: 3, nightscoutId: nil),
            syncIdentifier: "dose-1",
            isAutomatic: false,
            programmedUnits: 3
        )
        #expect(Guard.bolusCandidates(stored: [stored], pumpBolusInProgress: pump, pendingRemoteBolus: nil, now: now).count == 1)
    }

    @Test("A stored in-progress bolus with another identifier is not counted twice") func testInProgressDifferentIdentifiers() {
        let point3 = Decimal(string: "0.3")!
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)))
        let finished = Guard.StoredBolus(
            candidate: Candidate(date: minutes(-3), amount: point3, nightscoutId: objectId(at: minutes(-3))),
            syncIdentifier: "finished",
            isAutomatic: false,
            programmedUnits: point3
        )
        let storedInProgress = Guard.StoredBolus(
            candidate: Candidate(date: minutes(-1), amount: point3, nightscoutId: nil),
            syncIdentifier: "stored-row",
            isAutomatic: false,
            programmedUnits: point3
        )
        let pump = Guard.InFlightBolus(date: minutes(-1).addingTimeInterval(2), units: point3, syncIdentifier: "pump-dose")
        let pending = Guard.InFlightBolus(date: minutes(-1).addingTimeInterval(-1), units: point3, syncIdentifier: nil)

        let candidates = Guard.bolusCandidates(
            stored: [finished, storedInProgress],
            pumpBolusInProgress: pump,
            pendingRemoteBolus: pending,
            now: now
        )
        #expect(candidates.count == 2)
        #expect(
            Guard.evaluateBolus(requested: 1, boluses: candidates, context: ctx) ==
                .unknownInsulin(units: Decimal(string: "0.6")!, notUploadedOnly: false)
        )

        let otherAmount = Guard.InFlightBolus(date: pump.date, units: 1, syncIdentifier: "pump-dose")
        let automatic = Guard.StoredBolus(
            candidate: storedInProgress.candidate,
            syncIdentifier: "smb-row",
            isAutomatic: true,
            programmedUnits: point3
        )
        #expect(
            Guard.bolusCandidates(stored: [storedInProgress], pumpBolusInProgress: otherAmount, pendingRemoteBolus: nil, now: now)
                .count == 2
        )
        #expect(
            Guard.bolusCandidates(stored: [automatic], pumpBolusInProgress: pump, pendingRemoteBolus: nil, now: now)
                .count == 1
        )
    }

    @Test("Same bolus within 10 s and 0.025 U, inclusive at both edges") func testSameBolusEdges() {
        let date = minutes(-1)
        let point3 = NSNumber(value: 0.3).decimalValue
        let point325 = NSNumber(value: 0.325).decimalValue
        let point326 = Decimal(string: "0.326")!

        #expect(Guard.isSameBolus(date: date, units: point3, as: date.addingTimeInterval(10), units: point325))
        #expect(Guard.isSameBolus(date: date.addingTimeInterval(10), units: point325, as: date, units: point3))
        #expect(Guard.isSameBolus(
            date: date,
            units: Decimal(0.325 - 0.3 + 1),
            as: date,
            units: 1
        ))
        #expect(!Guard.isSameBolus(date: date, units: point3, as: date.addingTimeInterval(10.01), units: point3))
        #expect(!Guard.isSameBolus(date: date, units: point3, as: date, units: point326))

        let stored = Guard.StoredBolus(
            candidate: Candidate(date: date, amount: point3, nightscoutId: nil),
            syncIdentifier: "stored-row",
            isAutomatic: false,
            programmedUnits: point3
        )
        let edgePump = Guard.InFlightBolus(date: date.addingTimeInterval(10), units: point325, syncIdentifier: "pump-dose")
        let pastEdgePump = Guard.InFlightBolus(date: date.addingTimeInterval(10), units: point326, syncIdentifier: "pump-dose")
        #expect(
            Guard.bolusCandidates(stored: [stored], pumpBolusInProgress: edgePump, pendingRemoteBolus: nil, now: now)
                .count == 1
        )
        #expect(
            Guard.bolusCandidates(stored: [stored], pumpBolusInProgress: pastEdgePump, pendingRemoteBolus: nil, now: now)
                .count == 2
        )
    }

    @Test("An accepted remote bolus counts until the dose history holds it") func testPendingRemoteBolus() {
        let pending = Guard.InFlightBolus(date: minutes(-1), units: 2, syncIdentifier: nil)
        let smb = Guard.StoredBolus(
            candidate: Candidate(date: minutes(-0.5), amount: 0.25, nightscoutId: nil),
            syncIdentifier: "smb",
            isAutomatic: true,
            programmedUnits: 0.25
        )
        let manual = Guard.StoredBolus(
            candidate: Candidate(date: minutes(-0.5), amount: 2, nightscoutId: nil),
            syncIdentifier: "manual",
            isAutomatic: false,
            programmedUnits: 2
        )
        let pump = Guard.InFlightBolus(date: minutes(-0.5), units: 2, syncIdentifier: "manual")

        #expect(Guard.bolusCandidates(stored: [smb], pumpBolusInProgress: nil, pendingRemoteBolus: pending, now: now).count == 2)
        #expect(
            Guard.bolusCandidates(stored: [manual], pumpBolusInProgress: nil, pendingRemoteBolus: pending, now: now)
                .count == 1
        )
        #expect(Guard.bolusCandidates(stored: [], pumpBolusInProgress: pump, pendingRemoteBolus: pending, now: now).count == 1)
    }

    // MARK: - Messages

    @Test("Messages round insulin to 2 decimals and carbs to whole grams") func testMessageFormatting() {
        #expect(
            Guard.Decision.unknownInsulin(units: Decimal(string: "0.45")!, notUploadedOnly: true).rejectionMessage ==
                "Command rejected: 0.45 U of insulin has not been uploaded to Nightscout yet."
        )
        #expect(Guard.format(Decimal(string: "1.005")!, scale: 2) == "1.01")
        #expect(Guard.format(Decimal(string: "2.50")!, scale: 2) == "2.5")
        #expect(Guard.format(NSNumber(value: 7.3).decimalValue, scale: 0) == "7")
        #expect(
            Guard.Decision.unknownCarbs(count: 1, grams: NSNumber(value: 7.3).decimalValue).rejectionMessage ==
                "Command rejected: a carb entry of 7 g was recorded that you had not seen."
        )
        #expect(
            Guard.Decision.unknownCarbs(count: 2, grams: Decimal(string: "25.5")!).rejectionMessage ==
                "Command rejected: 2 carb entries totaling 26 g were recorded that you had not seen."
        )
        #expect(NSNumber(value: 7.3).decimalValue == Decimal(string: "7.3"))
    }

    // MARK: - Repeated commands

    @Test("A repeated command id is reported as already handled") func testRepeatedCommandId() {
        var handled = HandledRemoteCommands()

        let first = handled.markHandled("cmd-1", at: now)
        let repeated = handled.markHandled("cmd-1", at: now.addingTimeInterval(30))
        let other = handled.markHandled("cmd-2", at: now.addingTimeInterval(30))
        let afterRetention = handled.markHandled("cmd-1", at: now.addingTimeInterval(HandledRemoteCommands.retention + 1))

        #expect(first)
        #expect(!repeated)
        #expect(other)
        #expect(afterRetention)
    }

    @Test("Switching Nightscout site clears the cache and restarts recording") func testSiteSwitch() {
        var cache = NightscoutObjectIdCache(siteURL: "https://a.example", createdAt: minutes(-30))
        cache.record(localId: "bolus", objectId: objectId(at: minutes(-5)), at: now)
        #expect(cache.firstRecordedAt == minutes(-30))

        let sameSiteChanged = cache.switchSite(to: "https://a.example", at: now)
        #expect(!sameSiteChanged)
        #expect(cache.objectId(forLocalId: "bolus") != nil)
        #expect(cache.firstRecordedAt == minutes(-30))

        let otherSiteChanged = cache.switchSite(to: "https://b.example", at: now)
        #expect(otherSiteChanged)
        #expect(cache.objectId(forLocalId: "bolus") == nil)
        #expect(cache.firstRecordedAt == now)

        var withoutStart = NightscoutObjectIdCache(siteURL: "https://a.example")
        let startAdded = withoutStart.switchSite(to: "https://a.example", at: now)
        #expect(startAdded)
        #expect(withoutStart.firstRecordedAt == now)
        #expect(NightscoutObjectIdCache.normalizedSiteURL(" HTTPS://A.example/ ") == "https://a.example")
    }

    @Test("Recording starts when the store creates the cache for a site") func testRecordingStartsAtCacheCreation() throws {
        let suite = "RemoteTreatmentGuardTests-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        var configuredSite = "https://a.example"
        let store = NightscoutObjectIdStore(storage: storage) { configuredSite }

        #expect(store.snapshot(at: minutes(-60)).firstRecordedAt == minutes(-60))
        #expect(store.snapshot(at: minutes(-30)).firstRecordedAt == minutes(-60))
        store.record([("bolus", objectId(at: minutes(-5)))], fromSite: configuredSite, at: now)
        #expect(store.snapshot(at: now).firstRecordedAt == minutes(-60))

        let relaunched = NightscoutObjectIdStore(storage: storage) { configuredSite }
        #expect(relaunched.snapshot(at: now).firstRecordedAt == minutes(-60))

        configuredSite = "https://b.example"
        #expect(relaunched.snapshot(at: minutes(-2)).firstRecordedAt == minutes(-2))
        #expect(relaunched.snapshot(at: now).firstRecordedAt == minutes(-2))
        #expect(relaunched.snapshot(at: now).entries.isEmpty)
    }

    @Test("Store records mappings only for the configured site") func testStoreRecordsForConfiguredSite() throws {
        let suite = "RemoteTreatmentGuardTests-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let store = NightscoutObjectIdStore(storage: storage) { "https://a.example" }

        store.record([("other", objectId(at: minutes(-5)))], fromSite: "https://b.example", at: now)
        store.record([("none", objectId(at: minutes(-5)))], fromSite: nil, at: now)
        #expect(store.snapshot(at: now).entries.isEmpty)

        store.record([("bolus", objectId(at: minutes(-5)))], fromSite: "HTTPS://a.example/", at: now)
        #expect(store.snapshot().objectId(forLocalId: "bolus") == objectId(at: minutes(-5)))
        #expect(store.snapshot().firstRecordedAt == now)
    }

    @Test("Upload response arriving after a site change is not recorded") func testStoreIgnoresResponseFromPreviousSite() throws {
        let suite = "RemoteTreatmentGuardTests-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        var configuredSite = "https://a.example"
        let store = NightscoutObjectIdStore(storage: storage) { configuredSite }

        store.record([("old", objectId(at: minutes(-10)))], fromSite: "https://a.example", at: now)
        let requestSite = configuredSite
        configuredSite = "https://b.example"
        store.record([("late", objectId(at: minutes(-5)))], fromSite: requestSite, at: now)

        let snapshot = store.snapshot(at: now)
        #expect(snapshot.siteURL == "https://b.example")
        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.firstRecordedAt == now)

        store.record([("new", objectId(at: minutes(-1)))], fromSite: configuredSite, at: now)
        #expect(store.snapshot().objectId(forLocalId: "new") != nil)
        #expect(store.snapshot().objectId(forLocalId: "late") == nil)
    }

    // MARK: - Review fixes

    @Test("An _id in the marker's second counts by its full string") func testObjectIdFullStringComparison() {
        let second = minutes(-6)
        let marker = objectId(at: second, suffix: "0000000000000005")
        let ctx = context(sentAt: minutes(-5), knownThrough: marker)
        let sameSecondLater = Candidate(
            date: minutes(-60),
            amount: 1,
            nightscoutId: objectId(at: second, suffix: "0000000000000006")
        )
        let sameSecondEarlier = Candidate(
            date: minutes(-60),
            amount: 1,
            nightscoutId: objectId(at: second, suffix: "0000000000000004")
        )

        #expect(Guard.unknownReason(sameSecondLater, context: ctx) == .uploadedAfterMarker)
        #expect(Guard.unknownReason(sameSecondEarlier, context: ctx) == nil)
        #expect(Guard.unknownReason(Candidate(date: minutes(-60), amount: 1, nightscoutId: marker), context: ctx) == nil)
    }

    @Test("The marker rule uses creation time, so older future-dated entries are not judged by it") func testCreationTime() {
        let ctx = context(sentAt: minutes(-5), knownThrough: objectId(at: minutes(-6)), markerRuleStart: minutes(-30))
        let equivalentFromBefore = Candidate(date: minutes(60), amount: 10, nightscoutId: nil, createdAt: minutes(-90))
        let equivalentFromAfter = Candidate(date: minutes(60), amount: 10, nightscoutId: nil, createdAt: minutes(-20))

        #expect(Guard.evaluateCarbs(carbEntries: [equivalentFromBefore], context: ctx) == .allowed)
        #expect(Guard.evaluateCarbs(carbEntries: [equivalentFromAfter], context: ctx) == .unknownCarbs(count: 1, grams: 10))
        #expect(Candidate(date: minutes(1), amount: 1, nightscoutId: nil).createdAt == minutes(1))
    }

    @Test("The pump's bolus in progress matches a stored automatic bolus") func testInProgressMatchesAutomatic() {
        let smb = Guard.StoredBolus(
            candidate: Candidate(date: minutes(-1), amount: Decimal(string: "0.4")!, nightscoutId: nil),
            syncIdentifier: "smb-row",
            isAutomatic: true,
            programmedUnits: Decimal(string: "0.4")!
        )
        let pump = Guard.InFlightBolus(
            date: minutes(-1).addingTimeInterval(10),
            units: Decimal(string: "0.425")!,
            syncIdentifier: "pump"
        )
        let candidates = Guard.bolusCandidates(stored: [smb], pumpBolusInProgress: pump, pendingRemoteBolus: nil, now: now)

        #expect(candidates == [smb.candidate])
    }

    @Test("A pending remote bolus is dropped after 15 minutes") func testPendingExpiry() {
        let pending = Guard.InFlightBolus(date: minutes(-15), units: 2, syncIdentifier: nil)
        let expired = Guard.InFlightBolus(date: minutes(-15).addingTimeInterval(-1), units: 2, syncIdentifier: nil)

        #expect(Guard.activePendingBolus(pending, stored: [], pumpBolusInProgress: nil, now: now) == pending)
        #expect(Guard.activePendingBolus(expired, stored: [], pumpBolusInProgress: nil, now: now) == nil)
        #expect(Guard.bolusCandidates(stored: [], pumpBolusInProgress: nil, pendingRemoteBolus: expired, now: now).isEmpty)
        #expect(Guard.bolusCandidates(stored: [], pumpBolusInProgress: nil, pendingRemoteBolus: pending, now: now).count == 1)
    }

    @Test(
        "A pending remote bolus is dropped by a manual bolus from 10 s before it with units within 0.025 U"
    ) func testPendingDropRule() {
        let point3 = NSNumber(value: 0.3).decimalValue
        let point325 = NSNumber(value: 0.325).decimalValue
        let point326 = Decimal(string: "0.326")!
        let pending = Guard.InFlightBolus(date: minutes(-2), units: point3, syncIdentifier: nil)

        func stored(at date: Date, programmed: Decimal, automatic: Bool = false) -> Guard.StoredBolus {
            Guard.StoredBolus(
                candidate: Candidate(date: date, amount: programmed, nightscoutId: nil),
                syncIdentifier: UUID().uuidString,
                isAutomatic: automatic,
                programmedUnits: programmed
            )
        }
        func isDropped(by bolus: Guard.StoredBolus) -> Bool {
            Guard.activePendingBolus(pending, stored: [bolus], pumpBolusInProgress: nil, now: now) == nil
        }

        #expect(isDropped(by: stored(at: minutes(-2).addingTimeInterval(-10), programmed: point325)))
        #expect(isDropped(by: stored(at: minutes(-1), programmed: Decimal(string: "0.275")!)))
        #expect(!isDropped(by: stored(at: minutes(-2).addingTimeInterval(-10.01), programmed: point3)))
        #expect(!isDropped(by: stored(at: minutes(-1), programmed: point326)))
        #expect(!isDropped(by: stored(at: minutes(-1), programmed: point3, automatic: true)))
        #expect(!isDropped(by: stored(at: minutes(-1), programmed: 2)))

        let smbInProgress = Guard.InFlightBolus(date: minutes(-1), units: point3, syncIdentifier: "smb", isAutomatic: true)
        let manualInProgress = Guard.InFlightBolus(date: minutes(-1), units: point3, syncIdentifier: "manual")
        let otherInProgress = Guard.InFlightBolus(date: minutes(-1), units: 1, syncIdentifier: "manual")
        #expect(Guard.activePendingBolus(pending, stored: [], pumpBolusInProgress: smbInProgress, now: now) == pending)
        #expect(Guard.activePendingBolus(pending, stored: [], pumpBolusInProgress: otherInProgress, now: now) == pending)
        #expect(Guard.activePendingBolus(pending, stored: [], pumpBolusInProgress: manualInProgress, now: now) == nil)

        let candidates = Guard.bolusCandidates(
            stored: [],
            pumpBolusInProgress: smbInProgress,
            pendingRemoteBolus: pending,
            now: now
        )
        #expect(candidates.count == 2)
    }

    @Test("A pending remote bolus holds the amount rounded to the pump's bolus volume") func testPendingBolusRounding() {
        typealias Control = TrioRemoteControl
        let roundDownToTwentieth: (Double) -> Double = { ($0 / 0.05).rounded(.down) * 0.05 }

        #expect(
            Control.pendingBolusUnits(requested: Decimal(string: "1.27")!, roundToSupportedVolume: roundDownToTwentieth) ==
                NSNumber(value: roundDownToTwentieth(1.27)).decimalValue
        )
        #expect(
            Control
                .pendingBolusUnits(requested: Decimal(string: "1.27")!, roundToSupportedVolume: nil) == Decimal(string: "1.27")
        )

        let pending = Guard.InFlightBolus(
            date: minutes(-1),
            units: Control.pendingBolusUnits(requested: Decimal(string: "0.33")!, roundToSupportedVolume: roundDownToTwentieth),
            syncIdentifier: nil
        )
        let delivered = Guard.StoredBolus(
            candidate: Candidate(date: minutes(-1), amount: Decimal(string: "0.3")!, nightscoutId: nil),
            syncIdentifier: "manual",
            isAutomatic: false,
            programmedUnits: Decimal(string: "0.3")!
        )
        #expect(Guard.activePendingBolus(pending, stored: [delivered], pumpBolusInProgress: nil, now: now) == nil)
    }

    @Test(
        "A bolus dated after the send time counts also when dated after now; a carb entry does not"
    ) func testSendTimeRuleUpperBound() {
        let ctx = context(sentAt: minutes(-5))
        let aheadBolus = Candidate(date: minutes(3), amount: 1, nightscoutId: nil)
        let aheadCarbs = Candidate(date: minutes(3), amount: 20, nightscoutId: nil)

        #expect(Guard.unknownReason(aheadBolus, context: ctx, boundedByNow: false) == .afterSendTime)
        #expect(Guard.unknownReason(aheadCarbs, context: ctx) == nil)
        #expect(
            Guard.evaluateBolus(requested: 2, boluses: [aheadBolus], context: ctx) ==
                .unknownInsulin(units: 1, notUploadedOnly: false)
        )
        #expect(Guard.evaluateCarbs(carbEntries: [aheadCarbs], context: ctx) == .allowed)
    }

    @Test("Uncertain delivery and enacted boluses stay pending; refused ones are cleared") func testPendingPerResult() {
        typealias Control = TrioRemoteControl
        let uncertain = BolusEnactmentResult.failure(message: "m", error: PumpManagerError.uncertainDelivery)
        let wrappedUncertain = BolusEnactmentResult.failure(
            message: "m",
            error: APSError.pumpError(PumpManagerError.uncertainDelivery)
        )
        let refused = BolusEnactmentResult.failure(message: "m", error: PumpManagerError.communication(nil))

        guard case .uncertainDelivery = uncertain, case .uncertainDelivery = wrappedUncertain, case .failed = refused else {
            Issue.record("Unexpected classification")
            return
        }
        #expect(Control.keepsPendingRemoteBolus(after: .enacted(message: "ok")))
        #expect(Control.keepsPendingRemoteBolus(after: uncertain))
        #expect(!Control.keepsPendingRemoteBolus(after: refused))
        #expect(!Control.keepsPendingRemoteBolus(after: .failed(message: "no pump", error: nil)))
    }

    @Test("Failure replies for uncertain delivery and for a meal whose bolus failed") func testFailureReplies() {
        typealias Control = TrioRemoteControl
        let uncertain = BolusEnactmentResult.uncertainDelivery(message: "m", error: PumpManagerError.uncertainDelivery)
        let pumpError = PumpManagerError.deviceState(nil)
        let refused = BolusEnactmentResult.failed(message: "Error! Bolus failed with error: x", error: pumpError)

        #expect(
            Control.remoteBolusFailureMessage(for: uncertain, carbsStored: false) ==
                "Bolus may have been delivered. Check the history before sending another bolus."
        )
        #expect(
            Control.remoteBolusFailureMessage(for: uncertain, carbsStored: true) ==
                "Carbs were stored. Bolus may have been delivered. Check the history before sending another bolus."
        )
        #expect(Control.remoteBolusFailureMessage(for: refused, carbsStored: false) == "Error! Bolus failed with error: x")
        #expect(
            Control.remoteBolusFailureMessage(for: refused, carbsStored: true) ==
                "Carbs were stored, but the bolus failed: \(pumpError.localizedDescription)"
        )
        #expect(
            Control.remoteBolusFailureMessage(for: .failed(message: "No pump", error: nil), carbsStored: true) ==
                "Carbs were stored, but the bolus failed: No pump"
        )
    }

    @Test("Commands may be sent up to 12 minutes ago and 2 minutes ahead") func testTimeWindow() {
        typealias Control = TrioRemoteControl
        #expect(Control.timestampRejection(timeDifference: 720) == nil)
        #expect(
            Control
                .timestampRejection(timeDifference: 721) == "Command rejected: the message is too old (sent 721 seconds ago)."
        )
        #expect(Control.timestampRejection(timeDifference: -120) == nil)
        #expect(
            Control
                .timestampRejection(timeDifference: -121) == "Command rejected: the message has an invalid future timestamp."
        )
    }

    private func payload(_ json: String) throws -> CommandPayload {
        try JSONDecoder().decode(CommandPayload.self, from: Data(json.utf8))
    }

    @Test("Bolus and meal commands are deduplicated by command_id") func testCommandIdDedupe() throws {
        let bolus = try payload("""
        {"user":"c","command_type":"bolus","timestamp":1800000000,"bolus_amount":1,"command_id":"cmd-b"}
        """)
        let meal = try payload("""
        {"user":"c","command_type":"meal","timestamp":1800000000,"carbs":20,"bolus_amount":1,"command_id":"cmd-m"}
        """)
        var handled = HandledRemoteCommands()

        #expect(bolus.commandId == "cmd-b")
        let isFirst1 = handled.markHandled(bolus, at: now)
        #expect(isFirst1)
        let isFirst2 = handled.markHandled(bolus, at: now.addingTimeInterval(60 * 60))
        #expect(!isFirst2)
        let isFirst3 = handled.markHandled(meal, at: now)
        #expect(isFirst3)
        let isFirst4 = handled.markHandled(meal, at: now.addingTimeInterval(1))
        #expect(!isFirst4)
        let isFirst5 = handled.markHandled(bolus, at: now.addingTimeInterval(HandledRemoteCommands.retention + 1))
        #expect(isFirst5)
    }

    @Test("A handled command_id is recognised without recording it, also after the time window") func testHandledCommandIdLookup() throws {
        let bolus = try payload("""
        {"user":"c","command_type":"bolus","timestamp":1800000000,"bolus_amount":1,"command_id":"cmd-b"}
        """)
        let withoutId = try payload("""
        {"user":"c","command_type":"bolus","timestamp":1800000000,"bolus_amount":1}
        """)
        var handled = HandledRemoteCommands()

        #expect(!handled.handledCommandId(of: bolus, at: now))
        #expect(!handled.handledCommandId(of: bolus, at: now))
        _ = handled.markHandled(bolus, at: now)
        #expect(handled.handledCommandId(of: bolus, at: now.addingTimeInterval(20 * 60)))
        #expect(!handled.handledCommandId(of: bolus, at: now.addingTimeInterval(HandledRemoteCommands.retention + 1)))
        _ = handled.markHandled(withoutId, at: now)
        #expect(!handled.handledCommandId(of: withoutId, at: now))
    }

    @Test("Commands without command_id are deduplicated by send time, type and values within the window") func testContentDedupe() throws {
        let bolus = try payload("""
        {"user":"c","command_type":"bolus","timestamp":1800000000.25,"bolus_amount":1.5}
        """)
        let otherAmount = try payload("""
        {"user":"c","command_type":"bolus","timestamp":1800000000.25,"bolus_amount":1.55}
        """)
        let otherTime = try payload("""
        {"user":"c","command_type":"bolus","timestamp":1800000000.5,"bolus_amount":1.5}
        """)
        let meal = try payload("""
        {"user":"c","command_type":"meal","timestamp":1800000000.25,"carbs":20}
        """)
        var handled = HandledRemoteCommands()

        let isFirst6 = handled.markHandled(bolus, at: now)
        #expect(isFirst6)
        let isFirst7 = handled.markHandled(bolus, at: now.addingTimeInterval(HandledRemoteCommands.contentRetention - 1))
        #expect(!isFirst7)
        let isFirst8 = handled.markHandled(otherAmount, at: now)
        #expect(isFirst8)
        let isFirst9 = handled.markHandled(otherTime, at: now)
        #expect(isFirst9)
        let isFirst10 = handled.markHandled(meal, at: now)
        #expect(isFirst10)
        let isFirst11 = handled.markHandled(meal, at: now)
        #expect(!isFirst11)
        let isFirst12 = handled.markHandled(bolus, at: now.addingTimeInterval(HandledRemoteCommands.contentRetention + 1))
        #expect(isFirst12)
        #expect(HandledRemoteCommands.contentRetention == 840)
    }

    @Test("Remote commands run one at a time, in order") func testCommandQueueIsSerial() async throws {
        let queue = RemoteCommandQueue()
        let log = EventLog()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 5 {
                group.addTask {
                    try await queue.run {
                        await log.append("start \(index)")
                        try await Task.sleep(nanoseconds: 20_000_000)
                        await log.append("end \(index)")
                    }
                }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            try await group.waitForAll()
        }

        let events = await log.events
        #expect(events.count == 10)
        for pair in stride(from: 0, to: events.count, by: 2) {
            let start = events[pair].dropFirst("start ".count)
            #expect(events[pair].hasPrefix("start "))
            #expect(events[pair + 1] == "end \(start)")
        }
    }

    @Test("A failing command does not stop the next one") func testCommandQueueContinuesAfterError() async throws {
        let queue = RemoteCommandQueue()
        struct Failure: Error {}

        await #expect(throws: Failure.self) {
            try await queue.run { throw Failure() }
        }
        var ran = false
        try await queue.run { ran = true }
        #expect(ran)
    }

    @Test(
        "Missing _ids are looked up by local id, at most 10 per upload, for the current site only"
    ) func testResolveMissingObjectIds() async throws {
        let suite = "RemoteTreatmentGuardTests-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        var configuredSite = "https://a.example"
        let store = NightscoutObjectIdStore(storage: storage) { configuredSite }
        let known = objectId(at: Date().addingTimeInterval(-60))
        store.record([("known", known)], fromSite: configuredSite)

        let localIds = ["known"] + (0 ..< 12).map { "missing-\($0)" } + ["missing-0"]
        let lookups = EventLog()
        await store.resolveMissing(localIds: localIds, fromSite: "https://a.example/") { localId in
            await lookups.append(localId)
            return localId == "missing-1" ? nil : String(format: "%08x", UInt32(Date().timeIntervalSince1970)) +
                "00000000000000aa"
        }

        let looked = await lookups.events
        #expect(looked == (0 ..< 10).map { "missing-\($0)" })
        let snapshot = store.snapshot()
        #expect(snapshot.objectId(forLocalId: "known") == known)
        #expect(snapshot.objectId(forLocalId: "missing-0") != nil)
        #expect(snapshot.objectId(forLocalId: "missing-1") == nil)
        #expect(snapshot.objectId(forLocalId: "missing-10") == nil)

        let staleLookups = EventLog()
        await store.resolveMissing(localIds: ["late"], fromSite: "https://b.example") { localId in
            await staleLookups.append(localId)
            return nil
        }
        #expect(await staleLookups.events.isEmpty)

        configuredSite = "https://b.example"
        await store.resolveMissing(localIds: ["switched"], fromSite: "https://a.example") { _ in
            Issue.record("Lookup against a previous site")
            return nil
        }
        #expect(store.snapshot().entries.isEmpty)
    }

    @Test("The _id lookup asks for up to 100 treatments with the local id within the last 24 hours") func testObjectIdLookupQuery() {
        let since = Date(timeIntervalSince1970: 1_800_000_000)
        let items = NightscoutAPI.objectIdLookupQueryItems(localId: "abc", createdSince: since)

        #expect(items.first { $0.name == "find[id]" }?.value == "abc")
        #expect(
            items.first { $0.name == "find[created_at][$gte]" }?.value ==
                Formatter.iso8601withFractionalSeconds.string(from: since)
        )
        #expect(items.first { $0.name == "count" }?.value == "100")
    }

    @Test("The _id lookup returns the greatest _id with the local id") func testObjectIdLookupFetch() async throws {
        let api = NightscoutAPI(url: URL(string: "https://objectid-lookup.test")!)
        let older = objectId(at: minutes(-10))
        let newer = objectId(at: minutes(-5))
        LookupStubProtocol.responseBody = Data("""
        [{"_id":"\(older)","id":"abc"},{"_id":"\(newer)","id":"abc"},{"_id":"NA","id":"abc"},{"id":"abc"},
         {"_id":"\(objectId(at: minutes(-1)))","id":"other"}]
        """.utf8)
        URLProtocol.registerClass(LookupStubProtocol.self)
        defer { URLProtocol.unregisterClass(LookupStubProtocol.self) }

        let found = try await api.fetchObjectId(forLocalId: "abc", createdSince: minutes(-60))

        #expect(found == newer)
        let query = URLComponents(url: try #require(LookupStubProtocol.lastRequest?.url), resolvingAgainstBaseURL: false)
        #expect(query?.path == "/api/v1/treatments.json")
        #expect(query?.queryItems?.first { $0.name == "find[id]" }?.value == "abc")
    }

    // MARK: - Payload

    @Test("known_through_id decodes and is optional") func testPayloadDecoding() throws {
        let withMarker = try JSONDecoder().decode(CommandPayload.self, from: Data("""
        {"user":"caregiver","command_type":"bolus","timestamp":1700000000,"bolus_amount":1.5,
         "known_through_id":"65a1b2c3d4e5f60718293a4b"}
        """.utf8))
        let withoutMarker = try JSONDecoder().decode(CommandPayload.self, from: Data("""
        {"user":"caregiver","command_type":"bolus","timestamp":1700000000,"bolus_amount":1.5}
        """.utf8))

        #expect(withMarker.knownThroughId == "65a1b2c3d4e5f60718293a4b")
        #expect(withoutMarker.knownThroughId == nil)
    }
}

private actor EventLog {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

/// Answers requests to objectid-lookup.test with `responseBody`.
private final class LookupStubProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "objectid-lookup.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct AllowingBolusSafetyValidator: BolusSafetyValidator {
    func validate(bolusAmount _: Decimal) async throws -> BolusSafetyResult { .allowed }
    func validateLimits(bolusAmount _: Decimal) -> BolusSafetyResult { .allowed }
    func fetchTotalRecentBolusAmount(since _: Date) async throws -> Decimal { 0 }
}

private final class RemoteControlTestAssembly: Assembly {
    func assemble(container: Container) {
        container.register(BolusSafetyValidator.self) { _ in AllowingBolusSafetyValidator() }
    }
}

@Suite("Remote Treatment Guard Orchestration Tests", .serialized) struct RemoteTreatmentGuardOrchestrationTests {
    private let stack: CoreDataStack
    private let remoteControl: TrioRemoteControl

    init() async throws {
        stack = try await CoreDataStack.createForTests()
        let resolver = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: stack.newTaskContext()),
            RemoteControlTestAssembly()
        ]).resolver
        remoteControl = TrioRemoteControl(resolver: resolver)
        let stack = self.stack
        remoteControl.treatmentGuardStoreContext = { stack.newTaskContext() }
    }

    private func mealPayload(sentAt date: Date) throws -> CommandPayload {
        try JSONDecoder().decode(CommandPayload.self, from: Data("""
        {"user":"c","command_type":"meal","timestamp":\(date.timeIntervalSince1970),"carbs":20,"bolus_amount":1}
        """.utf8))
    }

    private func carbEntryCount() async throws -> Int {
        let context = stack.newTaskContext()
        return try await context.perform {
            try context.count(for: CarbEntryStored.fetchRequest())
        }
    }

    @Test("A meal whose bolus the guard rejects stores no carbs") func testMealGuardRunsBeforeStoring() async throws {
        let now = Date()
        let pending = RemoteTreatmentGuard.InFlightBolus(date: now.addingTimeInterval(-30), units: 2, syncIdentifier: nil)
        remoteControl.pendingRemoteBolus = pending

        try await remoteControl.handleMealCommand(mealPayload(sentAt: now.addingTimeInterval(-60)))

        #expect(try await carbEntryCount() == 0)
        #expect(remoteControl.pendingRemoteBolus == pending)
    }

    @Test("A meal stores carbs, then a bolus the pump refuses is no longer pending") func testMealStoresCarbsThenBolus() async throws {
        let now = Date()

        try await remoteControl.handleMealCommand(mealPayload(sentAt: now.addingTimeInterval(-60)))

        #expect(try await carbEntryCount() == 1)
        #expect(remoteControl.pendingRemoteBolus == nil)
    }

    @Test("An expired pending bolus is cleared when the guard reads it") func testExpiredPendingCleared() async throws {
        let expired = RemoteTreatmentGuard.InFlightBolus(
            date: Date().addingTimeInterval(-RemoteTreatmentGuard.pendingBolusRetention - 60),
            units: 2,
            syncIdentifier: nil
        )
        remoteControl.pendingRemoteBolus = expired
        let payload = try JSONDecoder().decode(CommandPayload.self, from: Data("""
        {"user":"c","command_type":"bolus","timestamp":\(Date().addingTimeInterval(-60).timeIntervalSince1970),"bolus_amount":1}
        """.utf8))

        let rejection = try await remoteControl.treatmentGuardRejection(for: payload, bolusAmount: 1, checkCarbs: true)

        #expect(rejection == nil)
        #expect(remoteControl.pendingRemoteBolus == nil)
    }

    @Test("A repeated command is reported to the app log only") func testRepeatedCommandNotReplied() throws {
        let payload = try JSONDecoder().decode(CommandPayload.self, from: Data("""
        {"user":"c","command_type":"bolus","timestamp":\(Date().timeIntervalSince1970),"bolus_amount":1,
         "command_id":"\(UUID().uuidString)"}
        """.utf8))

        #expect(remoteControl.markFirstHandling(of: payload, at: Date()))
        #expect(!remoteControl.markFirstHandling(of: payload, at: Date()))
    }

    private func storeBolus(at date: Date, programmed: Double, isSMB: Bool) async throws {
        let context = stack.newTaskContext()
        try await context.perform {
            let event = PumpEventStored(context: context)
            event.id = UUID().uuidString
            event.timestamp = date
            event.type = PumpEventStored.EventType.bolus.rawValue
            event.isMutable = false
            let bolus = BolusStored(context: context)
            bolus.amount = NSDecimalNumber(value: programmed)
            bolus.programmedAmount = NSDecimalNumber(value: programmed)
            bolus.isSMB = isSMB
            bolus.pumpEvent = event
            try context.save()
        }
    }

    private func bolusPayload(sentAt date: Date) throws -> CommandPayload {
        try JSONDecoder().decode(CommandPayload.self, from: Data("""
        {"user":"c","command_type":"bolus","timestamp":\(date.timeIntervalSince1970),"bolus_amount":1}
        """.utf8))
    }

    @Test("An SMB with the pending amount keeps the pending remote bolus") func testPendingKeptBySMB() async throws {
        let now = Date()
        let pending = RemoteTreatmentGuard.InFlightBolus(date: now.addingTimeInterval(-30), units: 2, syncIdentifier: nil)
        remoteControl.pendingRemoteBolus = pending
        try await storeBolus(at: now.addingTimeInterval(-20), programmed: 2, isSMB: true)

        _ = try await remoteControl.treatmentGuardRejection(
            for: bolusPayload(sentAt: now.addingTimeInterval(-60)),
            bolusAmount: 1,
            checkCarbs: false
        )

        #expect(remoteControl.pendingRemoteBolus == pending)
    }

    @Test("A manual bolus with the pending amount clears the pending remote bolus") func testPendingClearedByManual() async throws {
        let now = Date()
        let pending = RemoteTreatmentGuard.InFlightBolus(date: now.addingTimeInterval(-30), units: 2, syncIdentifier: nil)
        remoteControl.pendingRemoteBolus = pending
        try await storeBolus(at: now.addingTimeInterval(-35), programmed: 2, isSMB: false)

        let rejection = try await remoteControl.treatmentGuardRejection(
            for: bolusPayload(sentAt: now.addingTimeInterval(-60)),
            bolusAmount: 1,
            checkCarbs: false
        )

        #expect(remoteControl.pendingRemoteBolus == nil)
        #expect(rejection?.hasPrefix("Command rejected: 2 U of insulin") == true)
    }

    @Test("Fetched boluses and carb entries carry their _id and creation time") func testFetchHelpers() async throws {
        let now = Date()
        let context = stack.newTaskContext()
        let mealDate = now.addingTimeInterval(-90 * 60)
        let fpuId = UUID()
        let mealId = UUID()
        let equivalentId = UUID()
        try await context.perform {
            let event = PumpEventStored(context: context)
            event.id = "bolus-1"
            event.timestamp = now.addingTimeInterval(-60)
            event.type = PumpEventStored.EventType.bolus.rawValue
            event.isMutable = true
            let bolus = BolusStored(context: context)
            bolus.amount = NSDecimalNumber(value: 0.5)
            bolus.programmedAmount = NSDecimalNumber(value: 2)
            bolus.isSMB = true
            bolus.pumpEvent = event

            let meal = CarbEntryStored(context: context)
            meal.id = mealId
            meal.date = mealDate
            meal.carbs = 30
            meal.isFPU = false
            meal.fpuID = fpuId

            let equivalent = CarbEntryStored(context: context)
            equivalent.id = equivalentId
            equivalent.date = now.addingTimeInterval(60 * 60)
            equivalent.carbs = 10
            equivalent.isFPU = true
            equivalent.fpuID = fpuId

            let orphan = CarbEntryStored(context: context)
            orphan.id = UUID()
            orphan.date = now.addingTimeInterval(2 * 60 * 60)
            orphan.carbs = 5
            orphan.isFPU = true
            orphan.fpuID = UUID()

            try context.save()
        }

        var cache = NightscoutObjectIdCache(siteURL: "https://a.example")
        let bolusObjectId = String(format: "%08x", UInt32(now.timeIntervalSince1970)) + "0000000000000001"
        let fpuObjectId = String(format: "%08x", UInt32(now.timeIntervalSince1970)) + "0000000000000002"
        cache.record(localId: "bolus-1", objectId: bolusObjectId, at: now)
        cache.record(localId: fpuId.uuidString, objectId: fpuObjectId, at: now)
        let since = now.addingTimeInterval(-RemoteTreatmentGuard.lookback)

        let boluses = try await TrioRemoteControl.fetchTreatmentGuardBoluses(
            since: since,
            objectIds: cache,
            context: stack.newTaskContext()
        )
        #expect(boluses.count == 1)
        #expect(boluses.first?.candidate.amount == 2)
        #expect(boluses.first?.candidate.nightscoutId == bolusObjectId)
        #expect(boluses.first?.isAutomatic == true)
        #expect(boluses.first?.programmedUnits == 2)

        let carbs = try await TrioRemoteControl.fetchTreatmentGuardCarbEntries(
            since: since,
            objectIds: cache,
            context: stack.newTaskContext()
        )
        #expect(carbs.count == 3)
        let equivalent = try #require(carbs.first { $0.amount == 10 })
        #expect(equivalent.nightscoutId == fpuObjectId)
        #expect(equivalent.createdAt == mealDate)
        let meal = try #require(carbs.first { $0.amount == 30 })
        #expect(meal.nightscoutId == nil)
        #expect(meal.createdAt == mealDate)
        let orphan = try #require(carbs.first { $0.amount == 5 })
        #expect(orphan.createdAt == orphan.date)
    }
}
