import CoreData
import Darwin
import Foundation
import LoopKit
import Testing

@testable import Trio

@Suite(
    "Logging Long-Run Stress Tests",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["TRIO_STRESS"] == "1")
) struct LoggingLongRunStressTests {
    private typealias Fixtures = LoggingStressFixtures

    private class StubManager: DeviceManager {
        class var pluginIdentifier: String { LoggingStressFixtures.pumpManager }
        var localizedTitle: String { "Stress Pump" }
        var debugDescription: String { "## StubManager\npumpSN: \(LoggingStressFixtures.pumpSerial)" }
        var rawState: RawStateValue { [:] }
        var isOnboarded: Bool { true }

        init() {}
        required init?(rawState _: RawStateValue) {}

        func acknowledgeAlert(alertIdentifier _: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
            completion(nil)
        }

        func getSoundBaseURL() -> URL? { nil }
        func getSounds() -> [Alert.Sound] { [] }
        func initializationComplete(for _: [Pluggable]) {}
    }

    private final class StubCGMManager: StubManager {
        override class var pluginIdentifier: String { LoggingStressFixtures.cgmManager }
        override var localizedTitle: String { "Stress CGM" }
        override var debugDescription: String { "## StubCGMManager\ntransmitterID: \(LoggingStressFixtures.transmitterID)" }
    }

    private struct Dataset {
        let stack: CoreDataStack
        let end: Date
    }

    private struct Logs {
        let appLog: AppLogStore
        let deviceLog: DeviceLogStore
        let appURL: URL
        let deviceURL: URL
    }

    private actor Install {
        static let shared = Install()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LoggingLongRunStress", isDirectory: true)
        let end = Date()
        private var dataset: Dataset?
        private var logs: [String: Logs] = [:]

        func preparedDataset() async throws -> Dataset {
            if let dataset { return dataset }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stack = try await LoggingLongRunStressTests.buildDataset(
                end: end,
                storeURL: directory.appendingPathComponent("Trio.sqlite")
            )
            let dataset = Dataset(stack: stack, end: end)
            self.dataset = dataset
            return dataset
        }

        func preparedLogs(_ profile: StressProfile) async throws -> Logs {
            if let prepared = logs[profile.name] { return prepared }
            let prepared = try await LoggingLongRunStressTests.writeLogs(
                profile,
                end: end,
                directory: directory.appendingPathComponent(profile.name, isDirectory: true)
            )
            logs[profile.name] = prepared
            return prepared
        }

        func reset() {
            dataset = nil
            logs = [:]
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let clock = ContinuousClock()
    private static let logDays = 7
    private static let firstLogDay = Fixtures.days - logDays
    // The app deletes forecasts after 2 days and non-preset overrides after 3, at most once a day
    private static let shortLivedDays = 3
    private static let cyclePeriod: TimeInterval = 2
    private static let installID = "stress-watch-install"

    private static let entities = [
        "GlucoseStored", "OrefDetermination", "Forecast", "ForecastValue", "PumpEventStored", "TempBasalStored",
        "BolusStored", "CarbEntryStored", "OverrideStored", "OverrideRunStored", "TempTargetStored",
        "TempTargetRunStored", "TDDStored", "LoopStatRecord", "OpenAPS_Battery"
    ]

    // MARK: - 90-day Core Data install

    private struct Simulation {
        var rng = StressRandom(seed: 0x90DA)
        var noise = 0.0
        var previousGlucose = 120
        var iob = 0.0
        var lastTemp = Date.distantPast
        var lastRate = 0.0
        var resumeAt: Date?
        var tempTargetUntil = Date.distantPast
        var meals: [(date: Date, carbs: Double)] = []
        var reservoir = 180.0
        var battery = 100.0
    }

    private static func decimal(_ value: Double) -> NSDecimalNumber {
        NSDecimalNumber(value: Int((value * 100).rounded())).dividing(by: 100)
    }

    private static func step(_ value: Double, _ increment: Double) -> Double {
        (value / increment).rounded() * increment
    }

    private static func hourOfDay(_ date: Date) -> Double {
        date.timeIntervalSince1970.truncatingRemainder(dividingBy: Fixtures.day) / 3600
    }

    private static func scheduledBasal(at date: Date) -> Double {
        switch hourOfDay(date) {
        case ..<6: return 0.8
        case ..<10: return 1.1
        default: return 0.9
        }
    }

    private static func buildDataset(end: Date, storeURL: URL) async throws -> CoreDataStack {
        let stack = try await CoreDataStack.createForTests()
        let context = stack.newTaskContext()
        context.name = "stressDataset"
        var simulation = Simulation()
        var counts: [String: Int] = [:]

        let sampler = MemorySampler()
        let start = clock.now
        for day in 0 ..< Fixtures.days {
            let added = try insertDay(day, end: end, simulation: &simulation, into: context)
            counts.merge(added, uniquingKeysWith: +)
        }
        let insertDuration = clock.now - start

        let stored = try context.performAndWait {
            try Dictionary(uniqueKeysWithValues: entities.map { entity in
                (entity, try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity)))
            })
        }

        // The test stack lives in memory; moving it to a file gives a store size and real disk reads during export
        let migrateStart = clock.now
        let coordinator = stack.persistentContainer.persistentStoreCoordinator
        let memoryStore = try #require(coordinator.persistentStores.first)
        try? FileManager.default.removeItem(at: storeURL)
        _ = try coordinator.migratePersistentStore(memoryStore, to: storeURL, options: memoryStore.options, type: .sqlite)
        // The saved history token names the in-memory store, which no longer exists
        UserDefaults.standard.lastHistoryToken = nil
        let migrateDuration = clock.now - migrateStart
        let peak = sampler.stop()

        let window = DateInterval(start: end.addingTimeInterval(-7 * Fixtures.day), end: end)
        let fetchStart = clock.now
        let lines = await LogExport.algorithmLines(in: window, from: stack)
        let fetchDuration = clock.now - fetchStart

        Fixtures.report("dataset", [
            "days": "\(Fixtures.days)",
            "rows": "\(stored.values.reduce(0, +))",
            "perEntity": entities.map { "\($0):\(stored[$0] ?? 0)" }.joined(separator: ","),
            "insertSeconds": String(format: "%.1f", Fixtures.seconds(insertDuration)),
            "toFileSeconds": String(format: "%.1f", Fixtures.seconds(migrateDuration)),
            "peakFootprint": Fixtures.megabytes(peak.footprint),
            "sqlite+wal": Fixtures.megabytes(Fixtures.storeSize(storeURL)),
            "algorithmLines7d": "\(lines.count)",
            "algorithmLines7dSeconds": String(format: "%.2f", Fixtures.seconds(fetchDuration))
        ])
        for entity in entities {
            #expect(stored[entity] == counts[entity] ?? 0, "\(entity)")
        }
        #expect(stored["GlucoseStored"] == Fixtures.days * Fixtures.cyclesPerDay)
        #expect(stored["OrefDetermination"] == Fixtures.days * Fixtures.cyclesPerDay)
        return stack
    }

    private static func insertDay(
        _ day: Int,
        end: Date,
        simulation: inout Simulation,
        into context: NSManagedObjectContext
    ) throws -> [String: Int] {
        var sim = simulation
        defer { simulation = sim }
        let dayStart = Fixtures.dayStart(day, end: end)
        let keepsShortLived = day >= Fixtures.days - shortLivedDays
        var counts: [String: Int] = [:]

        // Offsets in seconds into the day, with fat and protein on main meals
        var carbPlan: [(offset: TimeInterval, carbs: Double, fat: Double, protein: Double)] = []
        func plan(_ hour: Double, _ carbs: ClosedRange<Int>, meal: Bool) {
            let offset = hour * 3600 + Double(Int.random(in: -2700 ... 2700, using: &sim.rng))
            let fat = meal ? Double(Int.random(in: 5 ... 40, using: &sim.rng)) : 0
            let protein = meal ? Double(Int.random(in: 5 ... 40, using: &sim.rng)) : 0
            carbPlan.append((offset, Double(Int.random(in: carbs, using: &sim.rng)), fat, protein))
        }
        if !sim.rng.chance(0.15) { plan(7.5, 20 ... 60, meal: true) }
        plan(12.5, 30 ... 80, meal: true)
        plan(18.5, 30 ... 90, meal: true)
        for _ in 0 ..< Int.random(in: 0 ... 3, using: &sim.rng) {
            plan(Double(Int.random(in: 9 ... 22, using: &sim.rng)), 10 ... 30, meal: false)
        }
        let carbCycles = Dictionary(grouping: carbPlan) { Int(max(0, $0.offset) / Fixtures.cycle) }

        let tempTargetCycle = sim.rng.chance(0.3) ? Int.random(in: 60 ..< 260, using: &sim.rng) : nil
        let overrideCycle = keepsShortLived && sim.rng.chance(0.6) ? Int.random(in: 60 ..< 260, using: &sim.rng) : nil

        try context.performAndWait {
            func count(_ entity: String, _ amount: Int = 1) {
                counts[entity, default: 0] += amount
            }

            func pumpEvent(_ type: PumpEventStored.EventType, at date: Date) -> PumpEventStored {
                let event = PumpEventStored(context: context)
                event.id = UUID().uuidString
                event.syncIdentifier = sim.rng.hex(bytes: 16)
                event.timestamp = date
                event.type = type.rawValue
                event.isMutable = false
                event.isUploadedToNS = true
                event.isUploadedToHealth = true
                event.isUploadedToTidepool = true
                count("PumpEventStored")
                return event
            }

            func bolus(_ amount: Double, at date: Date, smb: Bool, external: Bool = false) {
                let event = pumpEvent(.bolus, at: date)
                let bolus = BolusStored(context: context)
                bolus.amount = decimal(amount)
                bolus.programmedAmount = decimal(amount)
                bolus.isSMB = smb
                bolus.isExternal = external
                bolus.pumpEvent = event
                count("BolusStored")
                sim.iob += amount
            }

            if day == 0 {
                for (index, name) in ["Exercise", "Sick", "Sleep", "Pre-meal"].enumerated() {
                    let preset = OverrideStored(context: context)
                    preset.id = UUID().uuidString
                    preset.name = name
                    preset.date = dayStart
                    preset.isPreset = true
                    preset.percentage = [80, 120, 90, 100][index]
                    preset.duration = 60
                    preset.orderPosition = Int16(index)
                    count("OverrideStored")
                }
                for (index, target) in [140, 160, 80].enumerated() {
                    let preset = TempTargetStored(context: context)
                    preset.id = UUID()
                    preset.name = ["Activity", "Eating soon", "Hypo"][index]
                    preset.date = dayStart
                    preset.isPreset = true
                    preset.target = NSDecimalNumber(value: target)
                    preset.duration = 60
                    preset.orderPosition = Int16(index)
                    count("TempTargetStored")
                }
            }

            for cycleIndex in 0 ..< Fixtures.cyclesPerDay {
                let date = dayStart.addingTimeInterval(Double(cycleIndex) * Fixtures.cycle)

                for entry in carbCycles[cycleIndex] ?? [] {
                    let entryDate = dayStart.addingTimeInterval(max(0, entry.offset))
                    let carbs = CarbEntryStored(context: context)
                    carbs.id = UUID()
                    carbs.date = entryDate
                    carbs.carbs = entry.carbs
                    carbs.fat = entry.fat
                    carbs.protein = entry.protein
                    carbs.isUploadedToNS = true
                    carbs.isUploadedToHealth = true
                    carbs.isUploadedToTidepool = true
                    count("CarbEntryStored")
                    sim.meals.append((entryDate, entry.carbs))
                    if entry.fat + entry.protein >= 30 {
                        let fpuID = UUID()
                        carbs.fpuID = fpuID
                        let parts = Int.random(in: 3 ... 5, using: &sim.rng)
                        let equivalent = (entry.fat * 9 + entry.protein * 4) / 10
                        for part in 1 ... parts {
                            let fpu = CarbEntryStored(context: context)
                            fpu.id = UUID()
                            fpu.fpuID = fpuID
                            fpu.isFPU = true
                            fpu.date = entryDate.addingTimeInterval(Double(part) * 3600)
                            fpu.carbs = (equivalent / Double(parts)).rounded()
                            count("CarbEntryStored")
                        }
                    }
                    bolus(step(entry.carbs / 12 * 0.8, 0.05), at: entryDate.addingTimeInterval(20), smb: false)
                }

                if cycleIndex == tempTargetCycle {
                    let target = TempTargetStored(context: context)
                    target.id = UUID()
                    target.name = "Activity"
                    target.date = date
                    target.target = 140
                    target.duration = 60
                    target.enabled = false
                    target.isUploadedToNS = true
                    let run = TempTargetRunStored(context: context)
                    run.id = UUID()
                    run.name = "Activity"
                    run.startDate = date
                    run.endDate = date.addingTimeInterval(3600)
                    run.target = 140
                    run.tempTarget = target
                    count("TempTargetStored")
                    count("TempTargetRunStored")
                    sim.tempTargetUntil = date.addingTimeInterval(3600)
                }

                if cycleIndex == overrideCycle {
                    let override = OverrideStored(context: context)
                    override.id = UUID().uuidString
                    override.name = "Exercise"
                    override.date = date
                    override.percentage = 80
                    override.duration = 90
                    override.enabled = false
                    override.isUploadedToNS = true
                    let run = OverrideRunStored(context: context)
                    run.id = UUID()
                    run.name = "Exercise"
                    run.startDate = date
                    run.endDate = date.addingTimeInterval(5400)
                    run.override = override
                    count("OverrideStored")
                    count("OverrideRunStored")
                }

                sim.meals.removeAll { date.timeIntervalSince($0.date) > 4 * 3600 }
                var excursion = 0.0
                var cob = 0.0
                for meal in sim.meals {
                    let minutes = date.timeIntervalSince(meal.date) / 60
                    guard minutes >= 0 else { continue }
                    excursion += meal.carbs * 1.6 * (minutes / 60) * exp(1 - minutes / 60)
                    cob += meal.carbs * max(0, 1 - minutes / 180)
                }
                let hour = hourOfDay(date)
                let circadian = 12 * sin((hour - 4) / 24 * 2 * .pi) + (hour >= 3 && hour < 7 ? 15 : 0)
                sim.noise = 0.92 * sim.noise + Double(Int.random(in: -5 ... 5, using: &sim.rng))
                let glucose = Int(min(400, max(40, 110 + circadian + excursion - sim.iob * 6 + sim.noise)))
                let delta = glucose - sim.previousGlucose
                sim.previousGlucose = glucose

                let reading = GlucoseStored(context: context)
                reading.id = UUID()
                reading.date = date
                reading.glucose = Int16(glucose)
                reading.smoothedGlucose = NSDecimalNumber(value: glucose)
                reading.direction = switch delta {
                case ..<(-10): "DoubleDown"
                case ..<(-5): "SingleDown"
                case ..<(-2): "FortyFiveDown"
                case ...2: "Flat"
                case ...5: "FortyFiveUp"
                case ...10: "SingleUp"
                default: "DoubleUp"
                }
                reading.isUploadedToNS = true
                reading.isUploadedToHealth = true
                reading.isUploadedToTidepool = true
                count("GlucoseStored")

                if let resumeAt = sim.resumeAt, date >= resumeAt {
                    _ = pumpEvent(.pumpResume, at: date.addingTimeInterval(10))
                    sim.resumeAt = nil
                    sim.lastTemp = .distantPast
                } else if sim.resumeAt == nil, sim.rng.chance(1.0 / 600) {
                    _ = pumpEvent(.pumpSuspend, at: date.addingTimeInterval(10))
                    sim.resumeAt = date.addingTimeInterval(Double(Int.random(in: 15 ... 60, using: &sim.rng)) * 60)
                }
                let suspended = sim.resumeAt != nil

                if day % 3 == 0, cycleIndex == 19 * 12 {
                    _ = pumpEvent(.rewind, at: date.addingTimeInterval(60))
                    let prime = pumpEvent(.prime, at: date.addingTimeInterval(150))
                    prime.note = "Site change"
                    sim.reservoir = 180
                }
                if day % 7 == 2, cycleIndex == 150 {
                    bolus(2, at: date.addingTimeInterval(30), smb: false, external: true)
                }

                let isf = 55
                let ratio = [0.9, 1, 1, 1, 1.1][Int.random(in: 0 ... 4, using: &sim.rng)]
                let target = date < sim.tempTargetUntil ? 140 : 100
                let eventual = min(400, max(39, glucose + delta * 3 - Int(sim.iob * Double(isf) * 0.6) + Int(cob * 1.5)))
                let minPred = max(39, min(glucose, eventual) - Int.random(in: 0 ... 20, using: &sim.rng))
                let insulinReq = max(0, Double(eventual - target) / Double(isf))
                let scheduled = scheduledBasal(at: date)
                let wanted = eventual < target ? 0 : scheduled + insulinReq * 0.5
                let rate = suspended ? 0 : step(min(scheduled * 3, wanted), 0.05)
                let smbAmount = step(min(insulinReq * 0.5, 1.5), 0.05)
                let smb = !suspended && glucose > 110 && smbAmount >= 0.05 && sim.rng.chance(0.55) ? smbAmount : nil
                let deviation = delta * 6 + Int.random(in: -10 ... 10, using: &sim.rng)
                let bgi = -Int(sim.iob * 2)
                let deliverAt = date.addingTimeInterval(3)
                let enacted = !suspended && sim.rng.chance(0.95)

                let determination = OrefDetermination(context: context)
                determination.id = UUID()
                determination.deliverAt = deliverAt
                determination.timestamp = deliverAt
                determination.timestampEnacted = enacted ? deliverAt.addingTimeInterval(4) : nil
                determination.enacted = enacted
                determination.received = enacted
                determination.isUploadedToNS = true
                determination.glucose = NSDecimalNumber(value: glucose)
                determination.iob = decimal(sim.iob)
                determination.cob = Int16(cob.rounded())
                determination.rate = decimal(rate)
                determination.tempBasal = decimal(rate)
                determination.temp = "absolute"
                determination.duration = 30
                determination.smbToDeliver = smb.map(decimal)
                determination.eventualBG = NSDecimalNumber(value: eventual)
                determination.insulinReq = decimal(insulinReq)
                determination.insulinSensitivity = NSDecimalNumber(value: isf)
                determination.sensitivityRatio = decimal(ratio)
                determination.currentTarget = NSDecimalNumber(value: target)
                determination.threshold = 68
                determination.expectedDelta = decimal(Double(bgi) * 0.8)
                determination.minDelta = NSDecimalNumber(value: delta)
                determination.carbRatio = 12
                determination.scheduledBasal = decimal(scheduled)
                determination.reservoir = decimal(sim.reservoir)
                let cobPart = cob > 0 ? ", COBpredBG \(eventual + 10)" : ""
                let lowTemp = "Eventual BG \(eventual) < \(target), setting 30m low temp of \(rate)U/h. "
                let highTemp = "Eventual BG \(eventual) >= \(target),  insulinReq \(decimal(insulinReq)); " +
                    "setting 30m high temp of \(rate)U/h. "
                let action = eventual < target ? lowTemp : highTemp
                determination.reason = "Autosens ratio: \(ratio), ISF: \(isf)→\(Int(Double(isf) / ratio)), " +
                    "COB: \(Int(cob)), Dev: \(deviation), BGI: \(bgi), CR: 12, Target: \(target), minPredBG \(minPred), " +
                    "minGuardBG \(minPred + 9), IOBpredBG \(eventual - 27), UAMpredBG \(eventual)\(cobPart); " +
                    action + (smb.map { "Microbolusing \($0)U. " } ?? "")
                count("OrefDetermination")

                if keepsShortLived {
                    var types = ["IOB", "UAM", "ZT"]
                    if cob > 0 { types.append("COB") }
                    for type in types {
                        let forecast = Forecast(context: context)
                        forecast.id = UUID()
                        forecast.date = deliverAt
                        forecast.type = type
                        forecast.orefDetermination = determination
                        count("Forecast")
                        let length = switch type {
                        case "ZT": Int.random(in: 7 ... 48, using: &sim.rng)
                        case "UAM": 47
                        default: 48
                        }
                        for position in 0 ..< length {
                            let point = ForecastValue(context: context)
                            point.index = Int32(position)
                            point.value = Int32(glucose + (eventual - glucose) * position / 47)
                            point.forecast = forecast
                        }
                        count("ForecastValue", length)
                    }
                }

                if !suspended, enacted {
                    let sinceTemp = date.timeIntervalSince(sim.lastTemp)
                    if sinceTemp >= 30 * 60 || abs(rate - sim.lastRate) >= 0.1 && sinceTemp >= 5 * 60 && sim.rng.chance(0.6) {
                        let event = pumpEvent(.tempBasal, at: deliverAt.addingTimeInterval(4))
                        let temp = TempBasalStored(context: context)
                        temp.rate = decimal(rate)
                        temp.duration = 30
                        temp.startDate = deliverAt.addingTimeInterval(4)
                        temp.endDate = deliverAt.addingTimeInterval(4 + 30 * 60)
                        temp.tempType = "absolute"
                        temp.pumpEvent = event
                        count("TempBasalStored")
                        sim.lastTemp = date
                        sim.lastRate = rate
                    }
                    if let smb {
                        bolus(smb, at: deliverAt.addingTimeInterval(8), smb: true)
                    }
                }
                sim.iob = max(-1, sim.iob * 0.96 + (rate - scheduled) / 12)
                sim.reservoir = max(0, sim.reservoir - scheduled / 12 - (smb ?? 0))

                let tdd = TDDStored(context: context)
                tdd.id = UUID()
                tdd.date = deliverAt.addingTimeInterval(6)
                tdd.total = decimal(38 + Double(Int.random(in: -40 ... 40, using: &sim.rng)) / 10)
                tdd.bolus = decimal(18 + Double(Int.random(in: -30 ... 30, using: &sim.rng)) / 10)
                tdd.tempBasal = decimal(14)
                tdd.scheduledBasal = decimal(6)
                tdd.weightedAverage = decimal(37.5)
                count("TDDStored")

                let stat = LoopStatRecord(context: context)
                stat.start = date
                stat.end = deliverAt.addingTimeInterval(5)
                stat.duration = 8
                stat.interval = Fixtures.cycle
                stat.loopStatus = "Success"
                count("LoopStatRecord")

                sim.battery = sim.battery <= 20 ? 100 : sim.battery - 0.01
                let battery = OpenAPS_Battery(context: context)
                battery.id = UUID()
                battery.date = date
                battery.percent = sim.battery.rounded()
                battery.voltage = decimal(1.4)
                battery.status = "normal"
                battery.display = true
                count("OpenAPS_Battery")
            }
            try context.save()
            context.reset()
        }
        return counts
    }

    // MARK: - 7 days of logs

    private static func watchBatches(end: Date) -> [[WatchLogEntry]] {
        var rng = StressRandom(seed: 0x3A7C)
        let start = end.addingTimeInterval(-Double(logDays) * Fixtures.day)
        var batches: [[WatchLogEntry]] = []
        var batch: [WatchLogEntry] = []
        var seq: UInt64 = 0
        for cycleIndex in 0 ..< logDays * Fixtures.cyclesPerDay {
            let date = start.addingTimeInterval(Double(cycleIndex) * Fixtures.cycle + 45)
            func add(
                _ offset: TimeInterval,
                _ level: WatchLogEntry.Level,
                _ category: WatchLogEntry.Category,
                _ message: String
            ) {
                seq += 1
                batch
                    .append(WatchLogEntry(
                        seq: seq,
                        date: date.addingTimeInterval(offset),
                        level: level,
                        category: category,
                        message: message
                    ))
            }
            add(0, .debug, .data, "#w\(seq) Received state, BG \(Int.random(in: 60 ... 250, using: &rng)) mg/dL, IOB 1.2 U")
            add(0.2, .debug, .data, "#w\(seq) Complication updated")
            if rng.chance(0.3) { add(1, .info, .connectivity, "#w\(seq) Session reachable") }
            if rng.chance(0.01) { add(2, .warning, .connectivity, "#w\(seq) Phone not reachable, will retry") }
            if rng.chance(0.005) { add(3, .info, .bolus, "#w\(seq) Bolus of 1.5 U requested") }
            if rng.chance(0.004) { add(3, .info, .treatments, "#w\(seq) Carbs 20 g sent") }
            if rng.chance(0.002) { add(4, .info, .lifecycle, "#w\(seq) App became active") }
            // The watch sends its ring about every 30 minutes
            if cycleIndex % 6 == 5 {
                batches.append(batch)
                batch = []
            }
        }
        if !batch.isEmpty { batches.append(batch) }
        return batches
    }

    private static func writeLogs(_ profile: StressProfile, end: Date, directory: URL) async throws -> Logs {
        let appURL = directory.appendingPathComponent("logs/AppLog.sqlite")
        let deviceURL = directory.appendingPathComponent("logs/DeviceLog.sqlite")
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: appURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let appLog = AppLogStore(
            storageURL: appURL,
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        await appLog.flush()
        let sampler = MemorySampler()
        var appRecords = 0
        var appElapsed = Duration.zero
        for day in firstLogDay ..< Fixtures.days {
            let records = Fixtures.appRecords(day: day, end: end, profile: profile)
            let start = clock.now
            for chunk in stride(from: 0, to: records.count, by: 2000) {
                records[chunk ..< min(chunk + 2000, records.count)].forEach(appLog.accept)
                await appLog.flush()
            }
            appElapsed += clock.now - start
            appRecords += records.count
        }

        let suiteName = "LoggingLongRunStress-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ingest = WatchLogIngest(defaults: defaults, sink: { appLog })
        let staging = directory.appendingPathComponent("watch", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let batches = watchBatches(end: end)
        var watchRecords = 0
        let watchStart = clock.now
        for (index, entries) in batches.enumerated() {
            let file = staging.appendingPathComponent("received-\(index).jsonl")
            try WatchLogEntry.jsonLines(entries).write(to: file)
            let batch = try #require(WatchLogIngest.stage(file, metadata: [
                WatchLogTransfer.marker: NSNumber(value: WatchLogTransfer.version),
                WatchLogTransfer.installID: installID,
                WatchLogTransfer.firstSeq: NSNumber(value: entries.first?.seq ?? 0),
                WatchLogTransfer.lastSeq: NSNumber(value: entries.last?.seq ?? 0)
            ], into: staging))
            try? FileManager.default.removeItem(at: file)
            let ack = await ingest.ingest(batch)
            #expect(ack == entries.last?.seq)
            watchRecords += entries.count
        }
        let watchDuration = clock.now - watchStart

        let container = try #require(Fixtures.loadDeviceLogContainer(deviceURL))
        let context = container.newBackgroundContext()
        var counter: Int64 = 0
        var deviceEntries = 0
        let deviceStart = clock.now
        for day in firstLogDay ..< Fixtures.days {
            let entries = Fixtures.deviceEntries(day: day, end: end, profile: profile)
            try Fixtures.insert(entries, into: context, counter: &counter)
            deviceEntries += entries.count
        }
        let deviceDuration = clock.now - deviceStart
        Fixtures.unload(container)
        let deviceLog = DeviceLogStore(storageURL: deviceURL, isProtectedDataAvailable: { true })
        _ = await deviceLog.entries(in: DateInterval(start: end, duration: 1))
        let peak = sampler.stop()

        Fixtures.report("logs.\(profile.name)", [
            "appRecords": "\(appRecords)",
            "appRowsPerSec": String(format: "%.0f", Double(appRecords) / Fixtures.seconds(appElapsed)),
            "watchRecords": "\(watchRecords)",
            "watchBatches": "\(batches.count)",
            "watchIngestSeconds": String(format: "%.2f", Fixtures.seconds(watchDuration)),
            "deviceEntries": "\(deviceEntries)",
            "deviceInsertSeconds": String(format: "%.1f", Fixtures.seconds(deviceDuration)),
            "appSqlite+wal": Fixtures.megabytes(Fixtures.storeSize(appURL)),
            "deviceSqlite+wal": Fixtures.megabytes(Fixtures.storeSize(deviceURL)),
            "peakFootprint": Fixtures.megabytes(peak.footprint)
        ])
        let stored = rows(appURL, entity: "AppLogEntry", load: AppLogStore.loadContainer)
        #expect(stored == appRecords + watchRecords)
        return Logs(appLog: appLog, deviceLog: deviceLog, appURL: appURL, deviceURL: deviceURL)
    }

    // MARK: - Helpers

    private static func rows(
        _ url: URL,
        entity: String,
        load: (URL) -> NSPersistentContainer?,
        predicate: NSPredicate? = nil
    ) -> Int {
        guard let container = load(url) else { return -1 }
        defer { Fixtures.unload(container) }
        let context = container.newBackgroundContext()
        return context.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            request.predicate = predicate
            return (try? context.count(for: request)) ?? -1
        }
    }

    private static func oldest(_ url: URL, entity: String, load: (URL) -> NSPersistentContainer?) -> Date? {
        guard let container = load(url) else { return nil }
        defer { Fixtures.unload(container) }
        let context = container.newBackgroundContext()
        return context.performAndWait {
            let request = NSFetchRequest<NSDictionary>(entityName: entity)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["timestamp"]
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            request.fetchLimit = 1
            return (try? context.fetch(request))?.first?["timestamp"] as? Date
        }
    }

    // Purges may run in steps between other requests, so watch the store itself
    private static func waitForPurge(
        _ url: URL,
        entity: String,
        cutoff: Date,
        load: (URL) -> NSPersistentContainer?
    ) async -> Bool {
        let deadline = clock.now + .seconds(300)
        while clock.now < deadline {
            if let date = oldest(url, entity: entity, load: load), date >= cutoff.addingTimeInterval(-60) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private static func determinations(since date: Date, in stack: CoreDataStack) -> Int {
        let context = stack.newTaskContext()
        return context.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "OrefDetermination")
            request.predicate = NSPredicate(format: "deliverAt >= %@", date as NSDate)
            return (try? context.count(for: request)) ?? -1
        }
    }

    private static func expectedRows(_ source: String, since date: Date, logs: Logs, stack: CoreDataStack) -> Int {
        let since = NSPredicate(format: "timestamp >= %@", date as NSDate)
        let watch = NSPredicate(format: "category BEGINSWITH %@", WatchLogIngest.categoryPrefix)
        switch source {
        case "Trio":
            let notWatch = NSCompoundPredicate(notPredicateWithSubpredicate: watch)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [since, notWatch])
            return rows(logs.appURL, entity: "AppLogEntry", load: AppLogStore.loadContainer, predicate: predicate)
        case "Watch":
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [since, watch])
            return rows(logs.appURL, entity: "AppLogEntry", load: AppLogStore.loadContainer, predicate: predicate)
        case "Algorithm":
            return determinations(since: date, in: stack)
        default:
            let manager = source == "Pump" ? Fixtures.pumpManager : Fixtures.cgmManager
            let predicate = NSPredicate(format: "timestamp >= %@ AND managerIdentifier == %@", date as NSDate, manager)
            return rows(logs.deviceURL, entity: "Entry", load: Fixtures.loadDeviceLogContainer, predicate: predicate)
        }
    }

    private struct Analysis {
        var counts: [String: Int] = [:]
        var unsorted = 0
        var leaks: [String] = []
    }

    private static func analyze(_ text: String) -> Analysis {
        var analysis = Analysis()
        analysis.leaks = Fixtures.planted.filter { text.contains($0) }
        guard let range = text.range(of: "\n== Log ==\n") else { return analysis }
        let formatter = LogFileWriter.timestampFormatter()
        var previous: Substring = ""
        var previousDate = Date.distantPast
        for line in text[range.upperBound...].split(separator: "\n") {
            guard line.count > 30, line.first?.isNumber == true else { continue }
            let stamp = line.prefix(29)
            if previous.suffix(5) == stamp.suffix(5) {
                if stamp < previous { analysis.unsorted += 1 }
            } else if let date = formatter.date(from: String(stamp)) {
                if date < previousDate { analysis.unsorted += 1 }
                previousDate = date
            }
            previous = stamp
            let source = line.dropFirst(30).prefix { $0 != " " }
            analysis.counts[String(source), default: 0] += 1
        }
        return analysis
    }

    private static func zip(_ file: URL) throws -> URL {
        let folder = file.deletingLastPathComponent()
        let archive = folder.deletingLastPathComponent().appendingPathComponent("\(folder.lastPathComponent).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: archive)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return archive
    }

    private static func makeExport(_ logs: Logs, stack: CoreDataStack) -> LogExport {
        LogExport(
            appLog: logs.appLog,
            deviceLogStore: logs.deviceLog,
            pump: StubManager(),
            cgm: StubCGMManager(),
            storedValues: Fixtures.storedValues,
            coreDataStack: stack
        )
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }

    private static func milliseconds(_ seconds: Double) -> String {
        String(format: "%.1fms", seconds * 1000)
    }

    private static func microseconds(_ seconds: Double) -> String {
        String(format: "%.1fus", seconds * 1_000_000)
    }

    // MARK: - Tests

    @Test("A 90-day install fills the app's Core Data store") func dataset() async throws {
        await Install.shared.reset()
        _ = try await Install.shared.preparedDataset()
    }

    @Test(
        "Exports from a 90-day install are sorted, redacted, complete and within budget",
        arguments: [StressProfile.typical, .heavy]
    ) func exports(profile: StressProfile) async throws {
        let dataset = try await Install.shared.preparedDataset()
        let logs = try await Install.shared.preparedLogs(profile)
        let export = Self.makeExport(logs, stack: dataset.stack)

        for days in [1, 3, 7] {
            for kind in [LogExport.Kind.all, .pump, .cgm] {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )
                defer { try? FileManager.default.removeItem(at: directory) }
                let span = Double(days) * Fixtures.day
                let sources: [String] = switch kind {
                case .all: ["Trio", "Watch", "Pump", "CGM", "Algorithm"]
                case .pump: ["Pump"]
                case .cgm: ["CGM"]
                }
                let before = Date()
                let upper = Dictionary(uniqueKeysWithValues: sources.map {
                    ($0, Self.expectedRows($0, since: before.addingTimeInterval(-span), logs: logs, stack: dataset.stack))
                })
                let sampler = MemorySampler()
                let start = Self.clock.now
                let url = try await export.writeLog(kind, days: days, into: directory.appendingPathComponent("log"))
                let duration = Self.clock.now - start
                let peak = sampler.stop()
                let after = Date()
                let zipStart = Self.clock.now
                let archive = try Self.zip(url)
                let zipDuration = Self.clock.now - zipStart
                let textSize = Fixtures.fileSize(url)
                let zipSize = Fixtures.fileSize(archive)
                let analysis = Self.analyze(try String(contentsOf: url, encoding: .utf8))
                let name = "\(profile.name).\(kind)-\(days)d"

                Fixtures.report("longRunExport.\(name)", [
                    "seconds": String(format: "%.2f", Fixtures.seconds(duration)),
                    "zipSeconds": String(format: "%.2f", Fixtures.seconds(zipDuration)),
                    "peakFootprint": Fixtures.megabytes(peak.footprint),
                    "footprintGrowth": Fixtures.megabytes(peak.footprint - min(peak.footprint, sampler.baselineFootprint)),
                    "txt": Fixtures.megabytes(textSize),
                    "zip": Fixtures.megabytes(zipSize),
                    "lines": "\(analysis.counts.values.reduce(0, +))",
                    "sources": analysis.counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
                ])

                #expect(analysis.leaks.isEmpty, "\(name) leaks \(analysis.leaks)")
                #expect(analysis.unsorted == 0, "\(name)")
                #expect(Set(analysis.counts.keys) == Set(sources), "\(name)")
                for source in sources {
                    let lower = Self.expectedRows(
                        source,
                        since: after.addingTimeInterval(-span),
                        logs: logs,
                        stack: dataset.stack
                    )
                    let found = analysis.counts[source] ?? 0
                    let upperBound = upper[source] ?? 0
                    #expect(found >= lower && found <= upperBound, "\(name) \(source): \(found) not in \(lower)...\(upperBound)")
                }
                if kind == .all {
                    let expected = Self.determinations(since: after.addingTimeInterval(-span), in: dataset.stack)
                    #expect(analysis.counts["Algorithm"] == expected || analysis.counts["Algorithm"] == upper["Algorithm"])
                }
                let limit: Double = switch (kind, days) {
                case (.all, 1): 1.5
                case (.all, _): profile.name == StressProfile.heavy.name ? 8 : 5
                default: 2
                }
                #expect(Fixtures.seconds(duration) <= limit, "\(name) took \(duration)")
            }
        }
        await reportPhases(profile, logs: logs, stack: dataset.stack)
    }

    private func reportPhases(_ profile: StressProfile, logs: Logs, stack: CoreDataStack) async {
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-7 * Fixtures.day), end: now)
        let slices = LogFileWriter.slices(of: window)
        var phases: [String: Duration] = [:]
        func measure<T>(_ phase: String, _ body: () async throws -> T) async rethrows -> T {
            let start = Self.clock.now
            defer { phases[phase, default: .zero] += Self.clock.now - start }
            return try await body()
        }
        var values = Fixtures.storedValues
        for slice in slices {
            for entry in await measure("identifiers", { await logs.deviceLog.entries(in: slice) }) {
                values.add(entry.deviceIdentifier, .device)
            }
        }
        let redactor = Redactor(exactValues: values.values)
        let formatter = LogFileWriter.timestampFormatter()
        var bytes = 0
        for slice in slices {
            var lines = await measure("appFetch") { await logs.appLog.records(in: slice, minimumLevel: .debug) }
                .map(LogExport.line)
            lines += await measure("deviceFetch") {
                await logs.deviceLog.entries(in: slice).map { LogExport.line(for: $0, source: "Pump") }
            }
            lines += await measure("algorithm") { await LogExport.algorithmLines(in: slice, from: stack) }
            let sorted = await measure("sort") { lines.sorted { $0.date < $1.date } }
            let text = await measure("format") { sorted.map { LogFileWriter.format($0, formatter: formatter) }.joined() }
            bytes += await measure("redact") { redactor.redact(text) }.utf8.count
        }
        let total = phases.values.reduce(Duration.zero, +)
        Fixtures.report("longRunPhases.\(profile.name).all-7d", [
            "total": String(format: "%.2f", Fixtures.seconds(total)),
            "bytes": Fixtures.megabytes(UInt64(bytes)),
            "phases": phases.sorted { $0.value > $1.value }
                .map { "\($0.key):" + String(format: "%.2f", Fixtures.seconds($0.value)) }.joined(separator: ",")
        ])
    }

    private final class Stop: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        var isStopped: Bool { lock.withLock { stopped } }
        func stop() { lock.withLock { stopped = true } }
    }

    private struct CycleStats {
        var cycles = 0
        var lines = 0
        var logLatencies: [Double] = []
        var saves: [Double] = []
        var saveFailures = 0
    }

    // Each cycle saves glucose, a determination with forecasts and pump history, logs and talks to the pump
    private static func runCycles(
        tag: String,
        minimum: Int,
        until stop: Stop,
        stack: CoreDataStack,
        deviceLog: DeviceLogStore,
        profile: StressProfile
    ) async -> CycleStats {
        let context = stack.newTaskContext()
        context.name = "stressLoop"
        return await withCheckedContinuation { continuation in
            let thread = Thread {
                var stats = CycleStats()
                var rng = StressRandom(seed: 0x100F)
                var timebase = mach_timebase_info_data_t()
                mach_timebase_info(&timebase)

                func log(_ count: Int) {
                    for _ in 0 ..< count {
                        let message = "#\(tag).\(stats.lines) BG \(Int.random(in: 70 ... 220, using: &rng)) mg/dL, " +
                            "IOB 1.25 U, rate 0.85 U/h for 30 min"
                        let start = mach_absolute_time()
                        if stats.lines % 8 == 0 {
                            info(.loop, message)
                        } else {
                            debug(.algorithm, message)
                        }
                        let nanos = (mach_absolute_time() - start) * UInt64(timebase.numer) / UInt64(timebase.denom)
                        stats.logLatencies.append(Double(nanos) / 1E9)
                        stats.lines += 1
                    }
                }

                func save(_ body: () -> Void) {
                    let start = clock.now
                    context.performAndWait {
                        body()
                        do {
                            try context.save()
                        } catch {
                            stats.saveFailures += 1
                        }
                        context.reset()
                    }
                    stats.saves.append(Fixtures.seconds(clock.now - start))
                }

                while stats.cycles < minimum || !stop.isStopped {
                    let cycleStart = Date()
                    let glucose = Int.random(in: 70 ... 220, using: &rng)
                    save {
                        let reading = GlucoseStored(context: context)
                        reading.id = UUID()
                        reading.date = cycleStart
                        reading.glucose = Int16(glucose)
                        reading.direction = "Flat"
                    }
                    log(profile.linesPerCycle / 3)
                    save {
                        let determination = OrefDetermination(context: context)
                        determination.id = UUID()
                        determination.deliverAt = Date()
                        determination.timestamp = determination.deliverAt
                        determination.glucose = NSDecimalNumber(value: glucose)
                        determination.reason = "Autosens ratio: 1, ISF: 55→55, COB: 0, Dev: 4, BGI: -2, CR: 12, Target: 100"
                        for type in ["IOB", "UAM", "ZT"] {
                            let forecast = Forecast(context: context)
                            forecast.id = UUID()
                            forecast.date = determination.deliverAt
                            forecast.type = type
                            forecast.orefDetermination = determination
                            for position in 0 ..< 48 {
                                let point = ForecastValue(context: context)
                                point.index = Int32(position)
                                point.value = Int32(glucose)
                                point.forecast = forecast
                            }
                        }
                    }
                    log(profile.linesPerCycle / 3)
                    for pair in 0 ..< profile.pumpPairsPerCycle * 2 {
                        deviceLog.log(
                            managerIdentifier: Fixtures.pumpManager,
                            deviceIdentifier: Fixtures.pumpDevice,
                            type: pair % 2 == 0 ? .send : .receive,
                            message: "#\(tag)-dev.\(stats.cycles).\(pair) \(rng.hex(bytes: 12))"
                        )
                    }
                    save {
                        let event = PumpEventStored(context: context)
                        event.id = UUID().uuidString
                        event.timestamp = Date()
                        event.type = PumpEventStored.EventType.tempBasal.rawValue
                        let temp = TempBasalStored(context: context)
                        temp.rate = decimal(0.85)
                        temp.duration = 30
                        temp.startDate = event.timestamp
                        temp.pumpEvent = event
                        let tdd = TDDStored(context: context)
                        tdd.id = UUID()
                        tdd.date = Date()
                        tdd.total = 38
                        let stat = LoopStatRecord(context: context)
                        stat.start = cycleStart
                        stat.end = Date()
                        stat.loopStatus = "Success"
                    }
                    log(profile.linesPerCycle - 2 * (profile.linesPerCycle / 3))
                    stats.cycles += 1
                    let remaining = cyclePeriod - Date().timeIntervalSince(cycleStart)
                    if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
                }
                continuation.resume(returning: stats)
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private static func describe(_ stats: CycleStats) -> KeyValuePairs<String, String> {
        let latencies = stats.logLatencies.sorted()
        let saves = stats.saves.sorted()
        return [
            "cycles": "\(stats.cycles)",
            "logCalls": "\(stats.lines)",
            "logP50": microseconds(percentile(latencies, 0.5)),
            "logP99": microseconds(percentile(latencies, 0.99)),
            "logMax": microseconds(latencies.last ?? 0),
            "saves": "\(saves.count)",
            "saveP50": milliseconds(percentile(saves, 0.5)),
            "saveP99": milliseconds(percentile(saves, 0.99)),
            "saveMax": milliseconds(saves.last ?? 0),
            "saveFailures": "\(stats.saveFailures)"
        ]
    }

    @Test(
        "A loop cycle keeps logging and saving while a 90-day install exports",
        arguments: [StressProfile.typical, .heavy]
    ) func exportDuringLoop(profile: StressProfile) async throws {
        let dataset = try await Install.shared.preparedDataset()
        let logs = try await Install.shared.preparedLogs(profile)
        let export = Self.makeExport(logs, stack: dataset.stack)
        let previous = TrioLogger.sink
        TrioLogger.install(logs.appLog)
        defer { TrioLogger.install(previous) }

        let idleTag = "loop-idle-\(profile.name)"
        let idleStop = Stop()
        idleStop.stop()
        let idle = await Self.runCycles(
            tag: idleTag,
            minimum: 8,
            until: idleStop,
            stack: dataset.stack,
            deviceLog: logs.deviceLog,
            profile: profile
        )

        let busyTag = "loop-export-\(profile.name)"
        let stop = Stop()
        async let busy = Self.runCycles(
            tag: busyTag,
            minimum: 4,
            until: stop,
            stack: dataset.stack,
            deviceLog: logs.deviceLog,
            profile: profile
        )
        var exportSeconds: [String] = []
        for kind in [LogExport.Kind.all, .pump, .cgm] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let start = Self.clock.now
            _ = try await export.writeLog(kind, days: 7, into: directory)
            exportSeconds.append("\(kind):" + String(format: "%.2f", Fixtures.seconds(Self.clock.now - start)))
        }
        stop.stop()
        let during = await busy
        await logs.appLog.flush()

        Fixtures.report("loopIdle.\(profile.name)", Self.describe(idle))
        Fixtures.report("loopDuringExport.\(profile.name)", Self.describe(during))
        let idlePersisted = Self.rows(
            logs.appURL,
            entity: "AppLogEntry",
            load: AppLogStore.loadContainer,
            predicate: NSPredicate(format: "message BEGINSWITH %@", "#\(idleTag).")
        )
        let busyPersisted = Self.rows(
            logs.appURL,
            entity: "AppLogEntry",
            load: AppLogStore.loadContainer,
            predicate: NSPredicate(format: "message BEGINSWITH %@", "#\(busyTag).")
        )
        Fixtures.report("loopExports.\(profile.name)", [
            "exports7d": exportSeconds.joined(separator: ","),
            "persistedIdle": "\(idlePersisted)/\(idle.lines)",
            "persistedDuringExport": "\(busyPersisted)/\(during.lines)"
        ])

        let latencies = during.logLatencies.sorted()
        #expect(Self.percentile(latencies, 0.99) < 0.001)
        #expect(idle.saveFailures == 0 && during.saveFailures == 0)
        #expect((during.saves.max() ?? 0) < 1)
        #expect(idlePersisted == idle.lines)
        #expect(busyPersisted == during.lines)
    }

    private static func insertAppRecords(_ records: [LogRecord], into context: NSManagedObjectContext) throws {
        var iterator = records.makeIterator()
        let request = NSBatchInsertRequest(entityName: "AppLogEntry", dictionaryHandler: { dictionary in
            guard let record = iterator.next() else { return true }
            dictionary.addEntries(from: [
                "timestamp": record.timestamp,
                "level": record.level.rawValue,
                "category": record.category,
                "message": record.message,
                "file": record.file,
                "function": record.function,
                "line": Int32(clamping: record.line),
                "launchID": record.launchID
            ])
            return false
        })
        try context.performAndWait {
            _ = try context.execute(request)
        }
    }

    @Test(
        "Opening log stores with 7 fresh and 83 stale days purges to the retention age",
        arguments: [StressProfile.typical, .heavy]
    ) func launchPurge(profile: StressProfile) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoggingLongRunPurge-\(profile.name)",
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appURL = directory.appendingPathComponent("logs/AppLog.sqlite")
        let deviceURL = directory.appendingPathComponent("logs/DeviceLog.sqlite")
        try FileManager.default.createDirectory(at: appURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let end = Date()
        let cutoff = end.addingTimeInterval(-LogRetentionPolicy.default.maxAge)

        let buildStart = Self.clock.now
        var appRows = 0
        var freshAppRows = 0
        let appContainer = try #require(AppLogStore.loadContainer(appURL))
        let appContext = appContainer.newBackgroundContext()
        for day in 0 ..< Fixtures.days {
            let records = Fixtures.appRecords(day: day, end: end, profile: profile)
            try Self.insertAppRecords(records, into: appContext)
            appRows += records.count
            freshAppRows += records.filter { $0.timestamp >= cutoff }.count
        }
        Fixtures.unload(appContainer)
        var deviceRows = 0
        let deviceContainer = try #require(Fixtures.loadDeviceLogContainer(deviceURL))
        let deviceContext = deviceContainer.newBackgroundContext()
        var counter: Int64 = 0
        for day in 0 ..< Fixtures.days {
            let entries = Fixtures.deviceEntries(day: day, end: end, profile: profile)
            try Fixtures.insert(entries, into: deviceContext, counter: &counter)
            deviceRows += entries.count
        }
        Fixtures.unload(deviceContainer)
        let appSizeBefore = Fixtures.storeSize(appURL)
        let deviceSizeBefore = Fixtures.storeSize(deviceURL)
        Fixtures.report("stale.\(profile.name)", [
            "appRows": "\(appRows)",
            "deviceRows": "\(deviceRows)",
            "buildSeconds": String(format: "%.1f", Fixtures.seconds(Self.clock.now - buildStart)),
            "appSqlite+wal": Fixtures.megabytes(appSizeBefore),
            "deviceSqlite+wal": Fixtures.megabytes(deviceSizeBefore)
        ])

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        func acceptLatencies(_ body: (Int) -> Void) -> [Double] {
            (0 ..< 500).map { index in
                let start = mach_absolute_time()
                body(index)
                return Double((mach_absolute_time() - start) * UInt64(timebase.numer) / UInt64(timebase.denom)) / 1E9
            }.sorted()
        }

        let appSampler = MemorySampler()
        let appStart = Self.clock.now
        let appLog = AppLogStore(
            storageURL: appURL,
            notificationCenter: Foundation.NotificationCenter(),
            isProtectedDataAvailable: { true }
        )
        let appEarlyRequest = Task {
            let requested = Self.clock.now
            await appLog.flush()
            _ = await appLog.records(in: DateInterval(start: end.addingTimeInterval(-3600), end: Date()), minimumLevel: .debug)
            return Self.clock.now - requested
        }
        let appLatencies = acceptLatencies { index in
            appLog.accept(LogRecord(
                timestamp: Date(),
                level: .debug,
                category: "Loop",
                message: "#launch.\(index) logged during purge",
                file: "Stress.swift",
                function: "launch()",
                line: 1,
                launchID: LaunchID.current
            ))
        }
        let appEarlyWait = await appEarlyRequest.value
        let appPurged = await Self.waitForPurge(appURL, entity: "AppLogEntry", cutoff: cutoff, load: AppLogStore.loadContainer)
        await appLog.flush()
        let appDuration = Self.clock.now - appStart
        let appPeak = appSampler.stop()
        let appRemaining = Self.rows(appURL, entity: "AppLogEntry", load: AppLogStore.loadContainer)
        let appOldest = Self.oldest(appURL, entity: "AppLogEntry", load: AppLogStore.loadContainer)
        Fixtures.report("launchPurge.app.\(profile.name)", [
            "rowsBefore": "\(appRows)",
            "rowsAfter": "\(appRemaining)",
            "seconds": String(format: "%.2f", Fixtures.seconds(appDuration)),
            "earlyRequestWait": String(format: "%.2f", Fixtures.seconds(appEarlyWait)),
            "peakFootprint": Fixtures.megabytes(appPeak.footprint),
            "footprintGrowth": Fixtures.megabytes(appPeak.footprint - min(appPeak.footprint, appSampler.baselineFootprint)),
            "acceptP99": Self.microseconds(Self.percentile(appLatencies, 0.99)),
            "acceptMax": Self.microseconds(appLatencies.last ?? 0),
            "sqlite+walBefore": Fixtures.megabytes(appSizeBefore),
            "sqlite+walAfter": Fixtures.megabytes(Fixtures.storeSize(appURL))
        ])
        #expect(appPurged)
        #expect((appOldest ?? .distantPast) >= cutoff.addingTimeInterval(-60))
        #expect(appRemaining >= min(freshAppRows, LogRetentionPolicy.default.maxRows) - 2000)
        #expect(appRemaining <= LogRetentionPolicy.default.maxRows + 500)
        #expect(Self.percentile(appLatencies, 0.99) < 0.001)

        let deviceSampler = MemorySampler()
        let deviceStart = Self.clock.now
        let deviceLog = DeviceLogStore(storageURL: deviceURL, isProtectedDataAvailable: { true })
        let deviceEarlyRequest = Task {
            let requested = Self.clock.now
            _ = await deviceLog.entries(in: DateInterval(start: end.addingTimeInterval(-3600), end: Date()))
            return Self.clock.now - requested
        }
        let deviceLatencies = acceptLatencies { index in
            deviceLog.log(
                managerIdentifier: Fixtures.pumpManager,
                deviceIdentifier: Fixtures.pumpDevice,
                type: .send,
                message: "#launch-dev.\(index) logged during purge"
            )
        }
        let deviceEarlyWait = await deviceEarlyRequest.value
        let devicePurged = await Self.waitForPurge(
            deviceURL,
            entity: "Entry",
            cutoff: cutoff,
            load: Fixtures.loadDeviceLogContainer
        )
        _ = await deviceLog.entries(in: DateInterval(start: end, duration: 1))
        let deviceDuration = Self.clock.now - deviceStart
        let devicePeak = deviceSampler.stop()
        let deviceRemaining = Self.rows(deviceURL, entity: "Entry", load: Fixtures.loadDeviceLogContainer)
        let deviceOldest = Self.oldest(deviceURL, entity: "Entry", load: Fixtures.loadDeviceLogContainer)
        let retired = Self.rows(
            deviceURL,
            entity: "Entry",
            load: Fixtures.loadDeviceLogContainer,
            predicate: NSPredicate(format: "managerIdentifier == %@", Fixtures.retiredManager)
        )
        Fixtures.report("launchPurge.device.\(profile.name)", [
            "rowsBefore": "\(deviceRows)",
            "rowsAfter": "\(deviceRemaining)",
            "seconds": String(format: "%.2f", Fixtures.seconds(deviceDuration)),
            "earlyRequestWait": String(format: "%.2f", Fixtures.seconds(deviceEarlyWait)),
            "peakFootprint": Fixtures.megabytes(devicePeak.footprint),
            "footprintGrowth": Fixtures
                .megabytes(devicePeak.footprint - min(devicePeak.footprint, deviceSampler.baselineFootprint)),
            "logCallP99": Self.microseconds(Self.percentile(deviceLatencies, 0.99)),
            "logCallMax": Self.microseconds(deviceLatencies.last ?? 0),
            "sqlite+walBefore": Fixtures.megabytes(deviceSizeBefore),
            "sqlite+walAfter": Fixtures.megabytes(Fixtures.storeSize(deviceURL))
        ])
        #expect(devicePurged)
        #expect((deviceOldest ?? .distantPast) >= cutoff.addingTimeInterval(-60))
        #expect(retired == 0)
        #expect(Self.percentile(deviceLatencies, 0.99) < 0.001)
    }

    @Test("Clean up long-run stores") func cleanUp() async {
        await Install.shared.reset()
    }
}
