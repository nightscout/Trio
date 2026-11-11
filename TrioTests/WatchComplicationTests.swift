import Combine
import CoreData
import Foundation
import SwiftUI
import Swinject
import Testing
@testable import Trio
import WatchConnectivity

@Suite("Watch Complication") struct WatchComplicationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeModel(_ kind: ComplicationKind, _ state: ComplicationState, at date: Date) -> ComplicationModel {
        ComplicationModel(kind: kind, state: state, rendering: ComplicationRendering(referenceDate: date))
    }

    private func decodeSettings(_ json: String) throws -> TrioSettings {
        try JSONDecoder().decode(TrioSettings.self, from: Data(json.utf8))
    }

    @Test("Settings without complication keys use the defaults") func settingsDefaults() throws {
        let settings = try decodeSettings("{}")
        #expect(settings.watchComplicationCornerValue == WatchComplicationDefaults.cornerValue)
        #expect(settings.watchComplicationSecondaryValue == WatchComplicationDefaults.secondaryValue)
        #expect(settings.watchComplicationStaleMinutes == WatchComplicationDefaults.staleMinutes)
    }

    @Test("Stored complication settings decode") func settingsDecode() throws {
        let json = #"""
        {"watchComplicationCornerValue": "cob", "watchComplicationSecondaryValue": "loopAge",
         "watchComplicationStaleMinutes": 30}
        """#
        let settings = try decodeSettings(json)
        #expect(settings.watchComplicationCornerValue == .cob)
        #expect(settings.watchComplicationSecondaryValue == .loopAge)
        #expect(settings.watchComplicationStaleMinutes == 30)
    }

    @Test("Out-of-range stale minutes are clamped on decode") func staleMinutesClamped() throws {
        #expect(try decodeSettings(#"{"watchComplicationStaleMinutes": 0}"#).watchComplicationStaleMinutes == 10)
        #expect(try decodeSettings(#"{"watchComplicationStaleMinutes": 999}"#).watchComplicationStaleMinutes == 30)
        #expect(WatchComplicationDefaults.clampedStaleMinutes(-3) == 10)
        #expect(WatchComplicationDefaults.clampedStaleMinutes(30) == 30)
    }

    @Test("Grey Out After steps from 15 to exactly 10 and 30 and the footer explains the stale face") func greyOutAfterJourney() {
        let range = WatchComplicationDefaults.staleMinutesRange
        let step = WatchComplicationDefaults.staleMinutesStep
        #expect(WatchComplicationDefaults.staleMinutes == 15)
        #expect(range == 10 ... 30)
        #expect(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)) == [10, 15, 20, 25, 30])
        let footer = WatchConfigAppleWatchView.complicationSettingsFooter
        #expect(footer.contains("the glucose shows -- with the reading's age"))
        #expect(footer.contains("With the watch app closed"))
        #expect(footer.contains("the Contact Image updates with every reading"))
    }

    @Test("Clamping stays within 10 to 30 and is idempotent", arguments: -5 ... 40) func clampProperty(minutes: Int) {
        let clamped = WatchComplicationDefaults.clampedStaleMinutes(minutes)
        #expect(clamped == min(30, max(10, minutes)))
        #expect(WatchComplicationDefaults.clampedStaleMinutes(clamped) == clamped)
    }

    @Test("Snapshot round-trips through the store encoding") func snapshotRoundTrips() throws {
        let sample = ComplicationState.sample(
            units: "mg/dL",
            settings: ComplicationSlotSettings(cornerValue: .cob, secondaryValue: .loopAge, staleMinutes: 25),
            date: now
        )
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(ComplicationState.self, from: data)
        #expect(decoded == sample)
        #expect(!decoded.isMmol)
        #expect(decoded.history.count == 36)
        #expect(decoded.cornerValue == .cob)
        #expect(decoded.staleAfter == 25 * 60)
    }

    @Test("Units decide the gauge range and clamp the value") func gaugeRange() {
        var state = ComplicationState.sample(units: "mmol/L", date: now)
        #expect(state.gaugeRange == 2.5 ... 16.0)
        state.glucoseValue = 25
        #expect(state.gaugeValue == 16.0)
        state.glucoseValue = 1
        #expect(state.gaugeValue == 2.5)

        state = ComplicationState.sample(units: "mg/dL", date: now)
        #expect(state.gaugeRange == 45 ... 290)
        #expect(state.gaugeValue == 115)
    }

    @Test("Staleness follows the configured minutes") func staleness() {
        var state = ComplicationState.sample(units: "mg/dL", settings: ComplicationSlotSettings(staleMinutes: 10), date: now)
        #expect(!state.isStale(at: now.addingTimeInterval(9 * 60)))
        #expect(state.isStale(at: now.addingTimeInterval(11 * 60)))
        #expect(state.minutesAgo(at: now.addingTimeInterval(11 * 60)) == 11)
        state.staleMinutes = WatchComplicationDefaults.staleMinutes
        #expect(!state.isStale(at: now.addingTimeInterval(14 * 60)))
        #expect(state.isStale(at: now.addingTimeInterval(16 * 60)))
    }

    @Test("Staleness flips just after the configured minutes") func stalenessThreshold() {
        let settings = ComplicationSlotSettings(staleMinutes: 10)
        let state = ComplicationState.sample(units: "mg/dL", settings: settings, date: now)
        #expect(!state.isStale(at: now.addingTimeInterval(10 * 60)))
        #expect(state.isStale(at: now.addingTimeInterval(10 * 60 + 1)))
    }

    @Test("A stale reading is greyed") func staleReadingGreyed() {
        let settings = ComplicationSlotSettings(staleMinutes: 10)
        let state = ComplicationState.sample(units: "mg/dL", settings: settings, date: now)
        let fresh = makeModel(.glucose, state, at: now.addingTimeInterval(7 * 60))
        #expect(fresh.valueColor == .primary)
        #expect(fresh.dimColor == .secondary)
        let stale = makeModel(.glucose, state, at: now.addingTimeInterval(11 * 60))
        #expect(stale.glucoseColor == .gray)
        #expect(stale.valueColor == .gray)
        #expect(stale.dimColor == .gray)
    }

    @Test("A stale gauge replaces the glucose with dashes") func staleGauge() {
        let settings = ComplicationSlotSettings(staleMinutes: 10)
        let state = ComplicationState.sample(units: "mg/dL", settings: settings, date: now)
        let fresh = makeModel(.gauge, state, at: now.addingTimeInterval(10 * 60))
        #expect(fresh.glucoseText == "115")
        #expect(fresh.cornerMainText == "115")
        let stale = makeModel(.gauge, state, at: now.addingTimeInterval(10 * 60 + 1))
        #expect(stale.glucoseText == "--")
        #expect(stale.cornerMainText == "--")
    }

    @Test("Every kind hides a stale glucose") func staleGlucoseByKind() {
        var state = ComplicationState.sample(units: "mg/dL", date: now)
        state.trend = "Flat"
        let freshDate = now.addingTimeInterval(TimeInterval(state.staleMinutes * 60))
        let staleDate = now.addingTimeInterval(TimeInterval(state.staleMinutes * 60 + 1))
        #expect(makeModel(.glucose, state, at: freshDate).glucoseWithArrow == "115→")
        #expect(makeModel(.glucose, state, at: staleDate).glucoseWithArrow == "--")
        #expect(makeModel(.glucose, state, at: staleDate).cornerMainText == "--")
        #expect(makeModel(.chart, state, at: staleDate).glucoseText == "--")
        #expect(makeModel(.iob, state, at: staleDate).cornerMainText == "--")
    }

    @Test("Slot text follows the chosen value") func slotText() {
        var state = ComplicationState.sample(units: "mmol/L", date: now)
        state.trend = "FortyFiveUp"
        state.delta = "+0.3"
        #expect(state.trendArrow == "↗︎")
        #expect(state.labelledText(for: .nothing) == "")
        #expect(state.labelledText(for: .iob) == "IOB 1.25")
        #expect(state.plainText(for: .iob) == "1.25")
        #expect(state.labelledText(for: .cob) == "COB 12")
        #expect(state.labelledText(for: .delta) == "↗︎ +0.3")
        #expect(state.labelledText(for: .loopAge) == "Loop 2 min")
        state.trend = "Unknown"
        #expect(state.trendArrow == "")
        #expect(state.plainText(for: .delta) == "+0.3")
    }

    @Test("Loop staleness is separate from reading staleness") func loopStaleness() {
        var state = ComplicationState.sample(units: "mmol/L", settings: ComplicationSlotSettings(staleMinutes: 15), date: now)
        state.loopDate = now.addingTimeInterval(-20 * 60)
        let model = makeModel(.iob, state, at: now)
        #expect(!model.isStale)
        #expect(model.isLoopStale)
        #expect(model.valueColor == .gray)
        #expect(model.statusLine == "loop 20 min")
        state.loopDate = nil
        #expect(!state.isLoopStale(at: now.addingTimeInterval(3600)))
    }

    @Test("Loop age counts up from the loop date") func loopAge() {
        var state = ComplicationState.sample(units: "mg/dL", date: now)
        state.loopDate = now
        state.lastLoopTime = "1 min"
        #expect(state.loopAgeText(at: now.addingTimeInterval(7 * 60)) == "7 min")
        #expect(state.loopAgeText(at: now.addingTimeInterval(-60)) == "0 min")
        #expect(state.loopAgeText(at: now.addingTimeInterval(1440 * 60)) == "1440 min")
        #expect(state.loopAgeText(at: now.addingTimeInterval(1441 * 60)) == "--")
        let model = makeModel(.glucose, state, at: now.addingTimeInterval(7 * 60))
        #expect(model.displayedState.labelledText(for: .loopAge) == "Loop 7 min")

        state.loopDate = nil
        #expect(state.loopAgeText(at: now.addingTimeInterval(7 * 60)) == "1 min")
    }

    @Test("A stale loop replaces IOB and COB with dashes") func loopStaleValues() {
        var state = ComplicationState.sample(units: "mg/dL", settings: ComplicationSlotSettings(staleMinutes: 15), date: now)
        state.loopDate = now.addingTimeInterval(-15 * 60)
        var model = makeModel(.iob, state, at: now)
        #expect(model.displayedState.iob == "1.25")
        #expect(model.iobText == "1.25 U")
        #expect(model.cobText == "12 g")
        #expect(model.valueColor == .primary)

        state.loopDate = now.addingTimeInterval(-16 * 60)
        model = makeModel(.iob, state, at: now)
        #expect(model.displayedState.iob == "--")
        #expect(model.displayedState.cob == "--")
        #expect(model.iobText == "--")
        #expect(model.cobText == "--")
        #expect(model.displayedState.labelledText(for: .iob) == "IOB --")
        #expect(model.displayedState.plainText(for: .cob) == "--")
        #expect(model.valueColor == .gray)
    }

    @Test("A missing loop date greys IOB and COB but keeps their values") func loopUnknown() {
        var state = ComplicationState.sample(units: "mg/dL", date: now)
        state.loopDate = nil
        let model = makeModel(.iob, state, at: now)
        #expect(model.isLoopUnknown)
        #expect(!model.isLoopStale)
        #expect(model.displayedState.iob == "1.25")
        #expect(model.iobText == "1.25 U")
        #expect(model.valueColor == .gray)
        let rendering = ComplicationRendering(referenceDate: now, isPlaceholder: true)
        #expect(!ComplicationModel(kind: .iob, state: .placeholder, rendering: rendering).isLoopUnknown)
    }

    @Test("Ring and chart band follow the user's limits") func inRangeBand() {
        var state = ComplicationState.sample(units: "mg/dL", date: now)
        #expect(state.inRangeBand == 70 ... 180)
        state.limits = 80 ... 160
        #expect(state.inRangeBand == 80 ... 160)
        state.limits = nil
        #expect(state.inRangeBand == 70 ... 180)
        let model = makeModel(.gauge, state, at: state.date)
        #expect(model.gaugeGradient.stops.first?.color == .red)
        #expect(model.gaugeGradient.stops.count == 5)
    }

    @Test("Placeholder has no reading and a neutral colour") func placeholder() {
        let state = ComplicationState.placeholder
        #expect(state.gaugeValue == nil)
        let rendering = ComplicationRendering(referenceDate: now, isPlaceholder: true)
        let model = ComplicationModel(kind: .gauge, state: state, rendering: rendering)
        #expect(model.gaugeValue == (45.0 + 290.0) / 2)
        #expect(model.gaugeGradient == Gradient(colors: [.gray, .gray]))
        #expect(state.history.isEmpty)
        #expect(state.trendArrow == "")
        #expect(Color(complicationHex: "#4cd964") != nil)
        #expect(Color(complicationHex: "4cd964ff") == nil)
        #expect(Color(complicationHex: "zzz") == nil)
    }

    private func londonCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func londonDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        londonCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Transfers are spread over what is left of the day") func transferBudgetSpread() {
        let noon = londonDate(2026, 6, 1, 12)
        let spread: TimeInterval = 12 * 60 * 60 / 6
        func isDue(after elapsed: TimeInterval) -> Bool {
            ComplicationTransferBudget.isTransferDue(
                at: noon,
                lastTransfer: noon.addingTimeInterval(-elapsed),
                remainingTransfers: 6,
                calendar: londonCalendar()
            )
        }
        #expect(!isDue(after: spread - 1))
        #expect(isDue(after: spread))
    }

    @Test("A scarce budget is never spent faster than the spread") func transferBudgetScarce() {
        let noon = londonDate(2026, 6, 1, 12)
        let isDueAfterTwoHours = ComplicationTransferBudget.isTransferDue(
            at: noon,
            lastTransfer: noon.addingTimeInterval(-2 * 60 * 60),
            remainingTransfers: 1,
            calendar: londonCalendar()
        )
        #expect(!isDueAfterTwoHours)
    }

    @Test("Transfers keep a minimum gap late in the day") func transferBudgetMinimumGap() {
        let lateEvening = londonDate(2026, 6, 1, 23)
        func isDue(after elapsed: TimeInterval) -> Bool {
            ComplicationTransferBudget.isTransferDue(
                at: lateEvening,
                lastTransfer: lateEvening.addingTimeInterval(-elapsed),
                remainingTransfers: 50,
                calendar: londonCalendar()
            )
        }
        #expect(!isDue(after: 10 * 60 - 1))
        #expect(isDue(after: 10 * 60))
    }

    @Test("An empty budget never transfers") func transferBudgetExhausted() {
        #expect(!ComplicationTransferBudget.isTransferDue(at: now, lastTransfer: .distantPast, remainingTransfers: 0))
    }

    @Test("The day's end follows the clock on a 25 hour day") func transferBudgetClockChange() {
        let lateOnClockChange = londonDate(2026, 10, 25, 23).addingTimeInterval(30 * 60)
        let isDueAfterTwentyMinutes = ComplicationTransferBudget.isTransferDue(
            at: lateOnClockChange,
            lastTransfer: lateOnClockChange.addingTimeInterval(-20 * 60),
            remainingTransfers: 1,
            calendar: londonCalendar()
        )
        #expect(!isDueAfterTwentyMinutes)
    }

    @Test("The application context payload is a property list") func applicationContextIsPropertyList() throws {
        var state = WatchState(date: now)
        state.currentGlucose = "115"
        state.lastLoopDate = now
        state.lowGlucoseLimit = 70
        state.highGlucoseLimit = 180
        state.maxBolus = 2.5
        state.forecastLines = ["iob": [100, 110]]
        state.forecastStartDate = now
        let context = [WatchMessageKeys.watchState: BaseWatchManager.watchStateToDictionary(from: state)]
        let data = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0)
        #expect(!data.isEmpty)
    }

    @Test("Empty phone values become dashes") func emptyValuesBecomeDashes() {
        #expect(ComplicationState.presentOrMissing(nil) == "--")
        #expect(ComplicationState.presentOrMissing("") == "--")
        #expect(ComplicationState.presentOrMissing("1.25") == "1.25")
        var state = ComplicationState.sample(units: "mg/dL", date: now)
        state.iob = ComplicationState.presentOrMissing("")
        state.cob = ComplicationState.presentOrMissing("")
        let model = makeModel(.glucose, state, at: now)
        #expect(model.iobText == "--")
        #expect(model.cobText == "--")
        #expect(model.statusLine == "COB --")
        state.delta = ComplicationState.presentOrMissing("")
        #expect(state.labelledText(for: .delta) == "→ --")
        #expect(state.labelledText(for: .iob) == "IOB --")
        #expect(makeModel(.iob, state, at: now).cornerMainText == "--")
    }

    @Test("Stale data shows dashes in grey", arguments: ComplicationKind.allCases) func staleDataByKind(kind: ComplicationKind) {
        let state = ComplicationState.sample(units: "mg/dL", settings: ComplicationSlotSettings(staleMinutes: 10), date: now)
        let model = makeModel(kind, state, at: now.addingTimeInterval(10 * 60 + 1))
        #expect([model.glucoseText, model.iobText, model.cobText] == ["--", "--", "--"])
        #expect([model.glucoseColor, model.valueColor] == [.gray, .gray])
        #expect(model.gaugeGradient == Gradient(colors: [.gray, .gray]))
    }

    @Test("No app group without a resolved AppGroupID") func appGroupNeedsResolvedID() {
        #expect(ComplicationStore.appGroupID(from: nil) == nil)
        #expect(ComplicationStore.appGroupID(from: "") == nil)
        #expect(ComplicationStore.appGroupID(from: "$(APP_GROUP_ID)") == nil)
        #expect(ComplicationStore.appGroupID(from: "group.org.example.trio") == "group.org.example.trio")
    }

    @Test("Requests inside the debounce window build the watch state once") func watchStateRequestsCoalesce() {
        let scheduler = ManualScheduler()
        var builds = 0
        let updates = WatchStateUpdateCoalescer(interval: .seconds(2), scheduler: scheduler) { builds += 1 }
        updates.request()
        scheduler.advance(by: .seconds(1))
        updates.request()
        scheduler.advance(by: .seconds(2))
        #expect(builds == 1)
    }

    @Test("Reloading clears its flag after reloading only installed data kinds") func complicationReloadClearsFlag() {
        var finishFetch: ([String]) -> Void = { _ in }
        var reloadedKinds: [String] = []
        let reloader = ComplicationReloader(fetchInstalledKinds: { finishFetch = $0 }) { reloadedKinds.append($0) }
        reloader.reload(["TrioGlucoseComplication", "TrioGaugeComplication"])
        #expect(reloader.isReloading)
        finishFetch(["TrioGlucoseComplication", "SomeOtherWidget"])
        #expect(!reloader.isReloading)
        #expect(reloadedKinds == ["TrioGlucoseComplication"])
        reloader.reload(["TrioGlucoseComplication"])
        #expect(reloader.isReloading)
        finishFetch([])
        #expect(!reloader.isReloading)
        #expect(reloadedKinds == ["TrioGlucoseComplication"])
    }

    @Test("Each threshold gets a timeline entry", arguments: [10, 15, 20, 25, 30]) func staleTransitionAtThreshold(minutes: Int) {
        var state = ComplicationState.sample(units: "mg/dL", settings: ComplicationSlotSettings(staleMinutes: minutes), date: now)
        state.loopDate = now.addingTimeInterval(-2 * 60)
        let threshold = TimeInterval(minutes * 60)
        let expected = [now.addingTimeInterval(threshold + 1), now.addingTimeInterval(threshold - 2 * 60 + 1)]
        #expect(state.staleTransitionDates(after: now, within: 2 * 60 * 60) == expected)
    }

    @Test("Timeline has an entry when the reading and the loop go stale") func staleTransitionDates() {
        let settings = ComplicationSlotSettings(staleMinutes: 15)
        var state = ComplicationState.sample(units: "mg/dL", settings: settings, date: now)
        state.loopDate = now.addingTimeInterval(-2 * 60)
        let dates = state.staleTransitionDates(after: now, within: 2 * 60 * 60)
        #expect(dates.contains(now.addingTimeInterval(15 * 60 + 1)))
        #expect(dates.contains(now.addingTimeInterval(13 * 60 + 1)))
        #expect(state.staleTransitionDates(after: now.addingTimeInterval(20 * 60), within: 2 * 60 * 60).isEmpty)
        state.loopDate = nil
        #expect(state.staleTransitionDates(after: now, within: 2 * 60 * 60).count == 1)
    }
}

private final class ManualScheduler: Scheduler {
    typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType
    typealias Stride = SchedulerTimeType.Stride
    private(set) var now = SchedulerTimeType(DispatchTime(uptimeNanoseconds: 1))
    let minimumTolerance = Stride.zero
    private var pending: [(dueDate: SchedulerTimeType, action: () -> Void)] = []

    func schedule(options _: Never?, _ action: @escaping () -> Void) { action() }

    func schedule(after date: SchedulerTimeType, tolerance _: Stride, options _: Never?, _ action: @escaping () -> Void) {
        pending.append((date, action))
    }

    func schedule(
        after date: SchedulerTimeType,
        interval _: Stride,
        tolerance _: Stride,
        options _: Never?,
        _ action: @escaping () -> Void
    ) -> Cancellable {
        pending.append((date, action))
        return AnyCancellable {}
    }

    func advance(by interval: Stride) {
        now = now.advanced(by: interval)
        let due = pending.filter { $0.dueDate <= now }
        pending.removeAll { $0.dueDate <= now }
        due.forEach { $0.action() }
    }
}

@MainActor @Suite("Closed watch delivery", .serialized) struct ClosedWatchDeliveryTests {
    private let transport = FakeWatchTransport()
    private let entityChanges = PassthroughSubject<Set<NSManagedObjectID>, Never>()
    private let context: NSManagedObjectContext
    private let manager: BaseWatchManager

    init() async throws {
        context = try await CoreDataStack.createForTests().newTaskContext()
        let resolver = Assembler([
            StorageAssembly(), ServiceAssembly(), APSAssembly(), NetworkAssembly(), UIAssembly(), SecurityAssembly(),
            TestAssembly(testContext: context)
        ]).resolver
        manager = BaseWatchManager(
            resolver: resolver,
            entityChanges: entityChanges.eraseToAnyPublisher(),
            watchStateDebounce: .milliseconds(300)
        )
        manager.session = transport
        try await transport.discardStartupDeliveries(quietFor: 0.6)
    }

    private func entityChange(_ entityName: String) -> Set<NSManagedObjectID> {
        context.performAndWait { [NSEntityDescription.insertNewObject(forEntityName: entityName, into: context).objectID] }
    }

    @Test("With the watch app closed each phone change reaches the watch") func eachChangeReachesClosedWatch() async throws {
        manager.settingsDidChange(TrioSettings())
        try await transport.waitForApplicationContexts(1)
        manager.pumpSettingsDidChange(PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2))
        try await transport.waitForApplicationContexts(2)
        manager.snoozeDidChange(Date())
        try await transport.waitForApplicationContexts(3)
        entityChanges.send(entityChange("OverrideStored"))
        try await transport.waitForApplicationContexts(4)
        entityChanges.send(entityChange("TempTargetStored"))
        try await transport.waitForApplicationContexts(5)
        entityChanges.send(entityChange("GlucoseStored"))
        try await transport.waitForApplicationContexts(6)
        #expect(transport.applicationContexts.map(\.keys.first) == [String?](repeating: WatchMessageKeys.watchState, count: 6))
        #expect(transport.messages.isEmpty)
    }

    @Test("Six changes inside the debounce window reach a closed watch once") func changesInsideWindowReachOnce() async throws {
        manager.settingsDidChange(TrioSettings())
        manager.pumpSettingsDidChange(PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2))
        manager.snoozeDidChange(Date())
        entityChanges.send(entityChange("OverrideStored"))
        entityChanges.send(entityChange("TempTargetStored"))
        entityChanges.send(entityChange("GlucoseStored"))
        try await transport.waitForApplicationContexts(1)
        try await transport.waitForApplicationContexts(2, within: 1)
        #expect(transport.applicationContexts.count == 1)
    }
}

private final class FakeWatchTransport: WatchStateTransport {
    let isPaired = true
    let isWatchAppInstalled = true
    let isReachable = false
    let isComplicationEnabled = false
    let activationState = WCSessionActivationState.activated
    let remainingComplicationUserInfoTransfers = 0
    let outstandingUserInfoTransfers: [WCSessionUserInfoTransfer] = []
    private let lock = NSLock()
    private var recordedContexts: [[String: Any]] = []
    private var recordedMessages: [[String: Any]] = []

    var applicationContexts: [[String: Any]] { lock.withLock { recordedContexts } }
    var messages: [[String: Any]] { lock.withLock { recordedMessages } }

    func activate() {}

    func sendMessage(_ message: [String: Any], replyHandler _: (([String: Any]) -> Void)?, errorHandler _: ((Error) -> Void)?) {
        lock.withLock { recordedMessages.append(message) }
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        lock.withLock { recordedContexts.append(applicationContext) }
    }

    func transferUserInfo(_: [String: Any]) -> WCSessionUserInfoTransfer { WCSessionUserInfoTransfer() }

    func transferCurrentComplicationUserInfo(_: [String: Any]) -> WCSessionUserInfoTransfer { WCSessionUserInfoTransfer() }

    func waitForApplicationContexts(_ count: Int, within timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while applicationContexts.count < count, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func discardStartupDeliveries(quietFor interval: TimeInterval) async throws {
        var deliveredBefore = -1
        while deliveredBefore != applicationContexts.count {
            deliveredBefore = applicationContexts.count
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        lock.withLock { recordedContexts = [] }
    }
}
