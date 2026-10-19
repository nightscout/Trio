import CoreData
import Darwin
import Foundation
import LoopKit

@testable import Trio

struct StressRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    // SplitMix64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0 ..< 1, using: &self) < probability
    }

    mutating func hex(bytes: Int) -> String {
        (0 ..< bytes).map { _ in String(format: "%02hhx", UInt8.random(in: 0 ... 255, using: &self)) }.joined()
    }
}

enum LoggingStressFixtures {
    static let days = 90
    static let day: TimeInterval = 24 * 60 * 60
    static let cycle: TimeInterval = 5 * 60
    static let cyclesPerDay = Int(day / cycle)
    static let linesPerCycle = 60
    static let burstsPerDay = 4
    static let burstSize = 1000
    static let pumpPairsPerCycle = 34
    static let cgmPerCycle = 2
    static let retiredDays = 30
    static let forecastLength = 12

    static let siteURL = "https://stress-site.example.test/api"
    static let siteHost = "stress-site.example.test"
    static let token = "a1b2c3d4e5f60718293a4b5c6d7e8f9001122334"
    static let email = "stress.user@example.test"
    static let pumpSerial = "0a1b2c3d"
    static let podLot = "123456789"
    static let podTID = "7654321"
    static let transmitterID = "8GABCD"

    static let pumpManager = "StressPump"
    static let cgmManager = "StressCGM"
    static let retiredManager = "StressRetired"
    static let pumpDevice = "stress-pump-0001"
    static let cgmDevice = "stress-cgm-0001"
    static let retiredDevice = "stress-retired-0001"

    static let planted = [
        siteURL, siteHost, token, email, pumpSerial, podLot, podTID, transmitterID, pumpDevice, cgmDevice, retiredDevice
    ]

    private static let words = [
        "loop", "glucose", "basal", "temp", "bolus", "carbs", "forecast", "eventual", "target", "sensitivity",
        "ratio", "upload", "fetch", "pump", "status", "reservoir", "battery", "suspend", "resume", "override",
        "Ünïcödé", "Glukose", "血糖", "インスリン", "🩸", "📈", "✅", "⚠️", "💉", "🔋"
    ]
    private static let categories = Logger.Category.allCases.map(\.name)
    private static let functions = ["determineBasal()", "fetchGlucose()", "upload(_:)", "enact(_:)", "refresh()"]
    private static let files = [
        "APSManager.swift",
        "FetchGlucoseManager.swift",
        "NightscoutManager.swift",
        "DeviceDataManager.swift"
    ]

    static func dayStart(_ index: Int, end: Date) -> Date {
        end.addingTimeInterval(-Double(days - index) * day)
    }

    static func appRecords(day index: Int, end: Date) -> [LogRecord] {
        var rng = StressRandom(seed: 0xA11 &+ UInt64(index))
        let start = dayStart(index, end: end)
        let launchID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index % 256)))
        let burstCycles = Set((0 ..< burstsPerDay).map { _ in Int.random(in: 0 ..< cyclesPerDay, using: &rng) })
        var records: [LogRecord] = []
        records.reserveCapacity(cyclesPerDay * linesPerCycle + burstsPerDay * burstSize)

        func append(at date: Date, burst: Bool) {
            let level: LogLevel
            switch Double.random(in: 0 ..< 1, using: &rng) {
            case ..<0.001: level = .error
            case ..<0.021: level = .warning
            case ..<0.15: level = .info
            default: level = .debug
            }
            records.append(LogRecord(
                timestamp: date,
                level: level,
                category: categories.randomElement(using: &rng) ?? "Loop",
                message: "#a\(index).\(records.count) " + message(using: &rng, burst: burst),
                file: files.randomElement(using: &rng) ?? "",
                function: functions.randomElement(using: &rng) ?? "",
                line: UInt.random(in: 1 ... 2000, using: &rng),
                launchID: launchID
            ))
        }

        for cycleIndex in 0 ..< cyclesPerDay {
            let cycleStart = start.addingTimeInterval(Double(cycleIndex) * cycle)
            for line in 0 ..< linesPerCycle {
                append(at: cycleStart.addingTimeInterval(Double(line) * 0.5 + 0.001), burst: false)
            }
            if burstCycles.contains(cycleIndex) {
                let burstStart = cycleStart.addingTimeInterval(120)
                for line in 0 ..< burstSize {
                    append(at: burstStart.addingTimeInterval(Double(line) * 0.001), burst: true)
                }
            }
        }
        return records
    }

    static func secretMessage(_ index: Int) -> String {
        switch index % 9 {
        case 0: return "✅ Uploaded 12 entries to \(siteURL)/v1/entries.json?count=12 🚀"
        case 1: return "API secret hash \(token) accepted"
        case 2: return "Signed in as \(email)"
        case 3: return "Pump state pumpSN: \(pumpSerial) reservoir 120 U"
        case 4: return "Pod paired Lot: \(podLot) TID: \(podTID)"
        case 5: return "CGM transmitterID: \(transmitterID) battery ok"
        case 6: return "Connected to \(pumpDevice) after 2 retries"
        case 7: return "Reading from \(cgmDevice) 🩸 delta +3"
        default: return "Nightscout \(siteURL) answered 200\nbody: ok\ntoken \(token)"
        }
    }

    private static func message(using rng: inout StressRandom, burst: Bool) -> String {
        if rng.chance(0.005) {
            return secretMessage(Int.random(in: 0 ..< 9, using: &rng))
        }
        if !burst, rng.chance(0.0005) {
            return sentence(words: Int.random(in: 1500 ... 15000, using: &rng), using: &rng)
        }
        if rng.chance(0.02) {
            return (0 ..< Int.random(in: 3 ... 10, using: &rng))
                .map { _ in sentence(words: Int.random(in: 4 ... 16, using: &rng), using: &rng) }
                .joined(separator: "\n")
        }
        return sentence(words: Int.random(in: 5 ... 30, using: &rng), using: &rng)
    }

    private static func sentence(words count: Int, using rng: inout StressRandom) -> String {
        var text = ""
        text.reserveCapacity(count * 8)
        for index in 0 ..< count {
            if index > 0 { text += " " }
            if index % 7 == 3 {
                text += String(Int.random(in: 0 ... 400, using: &rng))
            } else {
                text += words.randomElement(using: &rng) ?? ""
            }
        }
        return text
    }

    static func deviceEntries(day index: Int, end: Date) -> [StoredDeviceLogEntry] {
        var rng = StressRandom(seed: 0xDE7 &+ UInt64(index))
        let start = dayStart(index, end: end)
        var entries: [StoredDeviceLogEntry] = []
        var pumpSequence = 0
        var cgmSequence = 0
        var retiredSequence = 0

        func pump(_ type: DeviceLogEntryType, _ text: String, at date: Date) {
            entries.append(StoredDeviceLogEntry(
                type: type,
                managerIdentifier: pumpManager,
                deviceIdentifier: pumpDevice,
                message: "#p\(index).\(pumpSequence) \(text)",
                timestamp: date
            ))
            pumpSequence += 1
        }

        for cycleIndex in 0 ..< cyclesPerDay {
            let cycleStart = start.addingTimeInterval(Double(cycleIndex) * cycle)
            for pair in 0 ..< pumpPairsPerCycle {
                let date = cycleStart.addingTimeInterval(1 + Double(pair) * 0.5)
                let opCode = Int.random(in: 1 ... 120, using: &rng)
                let sent = rng.hex(bytes: Int.random(in: 6 ... 32, using: &rng))
                let received = rng.hex(bytes: Int.random(in: 6 ... 32, using: &rng))
                pump(.send, "Sending data - Name: CMD_\(opCode), OpCode: \(opCode), Encoded data: \(sent)", at: date)
                pump(.receive, "Decoding successful! Data: \(received)", at: date.addingTimeInterval(0.05))
            }
            let event: (DeviceLogEntryType, String) = {
                switch cycleIndex % 4 {
                case 0: return (.connection, "Dana - Connection is ok! \(pumpDevice)")
                case 1: return (.delegate, "Enact temp basal, rate: 0.85U/h, duration: 30min")
                case 2: return (.delegateResponse, "Temp basal enacted pumpSN: \(pumpSerial)")
                default: return (.error, "Dana - Couldn't reconnect")
                }
            }()
            pump(event.0, event.1, at: cycleStart.addingTimeInterval(30))

            for reading in 0 ..< cgmPerCycle {
                let text = reading == 0
                    ? "Glucose \(Int.random(in: 60 ... 250, using: &rng)) mg/dL from \(cgmDevice) 📈"
                    : "transmitterID: \(transmitterID) battery ok"
                entries.append(StoredDeviceLogEntry(
                    type: .receive,
                    managerIdentifier: cgmManager,
                    deviceIdentifier: cgmDevice,
                    message: "#c\(index).\(cgmSequence) \(text)",
                    timestamp: cycleStart.addingTimeInterval(40 + Double(reading))
                ))
                cgmSequence += 1
            }

            if index < retiredDays {
                entries.append(StoredDeviceLogEntry(
                    type: .receive,
                    managerIdentifier: retiredManager,
                    deviceIdentifier: retiredDevice,
                    message: "#r\(index).\(retiredSequence) Legacy reading from \(retiredDevice)",
                    timestamp: cycleStart.addingTimeInterval(50)
                ))
                retiredSequence += 1
            }
        }
        return entries
    }

    static func loadDeviceLogContainer(_ url: URL) -> NSPersistentContainer? {
        guard let modelURL = Bundle(for: PersistentDeviceLog.self).url(forResource: "DeviceLog", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL)
        else { return nil }
        let container = NSPersistentContainer(name: "DeviceLog", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        return loadError == nil ? container : nil
    }

    static func unload(_ container: NSPersistentContainer) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
    }

    // Writes historical timestamps straight to the store; PersistentDeviceLog always stamps `Date()`
    static func insert(_ entries: [StoredDeviceLogEntry], into context: NSManagedObjectContext, counter: inout Int64) throws {
        var iterator = entries.makeIterator()
        var next = counter
        let request = NSBatchInsertRequest(entityName: "Entry", dictionaryHandler: { dictionary in
            guard let entry = iterator.next() else { return true }
            next += 1
            dictionary.addEntries(from: [
                "managerIdentifier": entry.managerIdentifier,
                "deviceIdentifier": entry.deviceIdentifier ?? "",
                "type": entry.type.rawValue,
                "message": entry.message,
                "timestamp": entry.timestamp,
                "modificationCounter": next
            ])
            return false
        })
        try context.performAndWait {
            _ = try context.execute(request)
        }
        counter = next
    }

    static func insertDeterminations(day index: Int, end: Date, into context: NSManagedObjectContext) throws {
        var rng = StressRandom(seed: 0x0DE7 &+ UInt64(index))
        let start = dayStart(index, end: end)
        try context.performAndWait {
            for cycleIndex in 0 ..< cyclesPerDay {
                let date = start.addingTimeInterval(Double(cycleIndex) * cycle + 3)
                let determination = OrefDetermination(context: context)
                determination.id = UUID()
                determination.deliverAt = date
                determination.timestamp = date
                determination.enacted = rng.chance(0.9)
                determination.glucose = NSDecimalNumber(value: Int.random(in: 60 ... 250, using: &rng))
                determination.iob = NSDecimalNumber(value: Double(Int.random(in: -50 ... 600, using: &rng)) / 100)
                determination.cob = Int16.random(in: 0 ... 80, using: &rng)
                determination.rate = NSDecimalNumber(value: Double(Int.random(in: 0 ... 300, using: &rng)) / 100)
                determination.duration = 30
                determination.eventualBG = NSDecimalNumber(value: Int.random(in: 60 ... 250, using: &rng))
                determination.reason = "COB: 0, Dev: 4, BGI: -1, ISF: 54, CR: 9, Target: 100, minPredBG 98, IOBpredBG 101"
                for type in ["iob", "cob", "uam", "zt"] {
                    let forecast = Forecast(context: context)
                    forecast.id = UUID()
                    forecast.date = date
                    forecast.type = type
                    forecast.orefDetermination = determination
                    var value = Int32.random(in: 80 ... 180, using: &rng)
                    for position in 0 ..< forecastLength {
                        let point = ForecastValue(context: context)
                        point.index = Int32(position)
                        point.value = value
                        point.forecast = forecast
                        value += Int32.random(in: -6 ... 6, using: &rng)
                    }
                }
            }
            try context.save()
            context.reset()
        }
    }

    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func storeSize(_ url: URL) -> UInt64 {
        ["", "-wal", "-shm"].reduce(0) { total, suffix in
            total + fileSize(URL(fileURLWithPath: url.path + suffix))
        }
    }

    static func fileSize(_ url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }

    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1E18
    }

    static func report(_ name: String, _ values: KeyValuePairs<String, String>) {
        print("STRESS: \(name) " + values.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    }
}

final class MemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var peakResident: UInt64 = 0
    private var peakFootprint: UInt64 = 0
    let baselineFootprint = LoggingStressFixtures.footprintBytes()

    init() {
        let thread = Thread { [self] in
            while lock.withLock({ running }) {
                sample()
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func sample() {
        let resident = LoggingStressFixtures.residentBytes()
        let footprint = LoggingStressFixtures.footprintBytes()
        lock.withLock {
            peakResident = max(peakResident, resident)
            peakFootprint = max(peakFootprint, footprint)
        }
    }

    func stop() -> (resident: UInt64, footprint: UInt64) {
        sample()
        return lock.withLock {
            running = false
            return (peakResident, peakFootprint)
        }
    }
}
