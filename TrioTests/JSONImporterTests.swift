//
//  JSONImporterTests.swift
//  Trio
//
//  Created by Cengiz Deniz on 21.04.25.
//
import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("JSON Importer Tests") struct JSONImporterTests: Injectable {
    let resolver: Resolver = TrioApp().resolver
    var coreDataStack: CoreDataStack!
    var context: NSManagedObjectContext!
    var importer: JSONImporter!
    let fileManager = FileManager.default
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    @Injected() var fileStorage: FileStorage!

    init() async throws {
        injectServices(resolver)

        // In-memory Core Data for tests
        coreDataStack = try await CoreDataStack.createForTests()
        context = coreDataStack.newTaskContext()
        importer = JSONImporter(context: context)

        // Clear import flags and remove fixtures
        let flags = [
            "pumpHistoryImported",
            "carbHistoryImported",
            "glucoseHistoryImported",
            "enactedHistoryImported"
        ]
        flags.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        let comps = [
            OpenAPS.Monitor.pumpHistory,
            OpenAPS.Monitor.carbHistory,
            OpenAPS.Monitor.glucose,
            OpenAPS.Enact.enacted
        ]
        comps.forEach { try? fileManager.removeItem(at: documentsURL.appendingPathComponent($0)) }
    }

    private let iso8601WithFractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // ensure it parses the full internet date+time with milliseconds
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Parses an ISO‑8601 string (e.g. "2025-04-17T10:00:00.000Z") into a `Date`.
    /// - Parameter isoString: the ISO‑8601 date string.
    /// - Returns: a `Date` if parsing succeeds, or `nil` otherwise.
    func dateFromISOString(_ isoString: String) -> Date? {
        iso8601WithFractionalSecondsFormatter.date(from: isoString)
    }

    @Test("Import pump history with value checks") func testImportPumpHistoryDetails() async throws {
        let pumpHistory = [
            PumpHistoryEvent(
                id: "9DDAA42F-465C-4812-9422-9933FB1CC290",
                type: .bolus,
                timestamp: dateFromISOString("2025-04-17T10:00:00.000Z") ?? Date(),
                amount: 1.0,
                duration: 0,
                isSMB: false,
                isExternal: true
            ),
            PumpHistoryEvent(
                id: "F958F9A5-78F3-4B6C-AF6C-5B580BBB8A29",
                type: .bolus,
                timestamp: dateFromISOString("2025-04-17T10:01:00.000Z") ?? Date(),
                amount: 2.0,
                duration: 0,
                isSMB: false,
                isExternal: false
            ),
            PumpHistoryEvent(
                id: "CCBE1CDA-EE13-4D7C-8CCC-7361EC9C979D",
                type: .bolus,
                timestamp: dateFromISOString("2025-04-17T10:02:00.000Z") ?? Date(),
                amount: 3.0,
                duration: 0,
                isSMB: true,
                isExternal: false
            ),
            PumpHistoryEvent(
                id: "0FB76585-B6A4-4659-BDD2-B673BE6DD549",
                type: .tempBasalDuration,
                timestamp: dateFromISOString("2025-04-17T10:05:00.000Z") ?? Date(),
                duration: 30
            ),
            PumpHistoryEvent(
                id: "_0FB76585-B6A4-4659-BDD2-B673BE6DD549",
                type: .tempBasal,
                timestamp: dateFromISOString("2025-04-17T10:05:00.000Z") ?? Date(),
                amount: 1.5,
                duration: 0,
                temp: .absolute
            ),
            PumpHistoryEvent(
                id: "24909A93-0BC7-46D0-837F-9B2028E22BFC",
                type: .pumpSuspend,
                timestamp: dateFromISOString("2025-04-17T10:10:00.000Z") ?? Date()
            ),
            PumpHistoryEvent(
                id: "BDEF7F55-48FE-447D-876C-19260ADE5ECA",
                type: .pumpResume,
                timestamp: dateFromISOString("2025-04-17T10:10:00.000Z") ?? Date()
            ),
            PumpHistoryEvent(
                id: "1CAEEFA3-D740-4EA0-83B4-D28860991639",
                type: .rewind,
                timestamp: dateFromISOString("2025-04-17T10:10:00.000Z") ?? Date()
            ),
            PumpHistoryEvent(
                id: "CD019C44-57F0-4CB0-BBDF-8B6C40A48E99",
                type: .prime,
                timestamp: dateFromISOString("2025-04-17T10:10:00.000Z") ?? Date()
            )
        ]

        fileStorage.save(pumpHistory, as: OpenAPS.Monitor.pumpHistory)

        // Import
        await importer.importPumpHistoryIfNeeded()

        // Fetch all imported events
        let events = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "timestamp",
            ascending: true
        ) as? [PumpEventStored] ?? []

        // Verify total count
        #expect(events.count == 8, "Should import all 8 pump events") // TBR should be combination of TB duration and TBR, so 8, not 9

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Verify the three Boluses
        let bolusEvents = events.filter { $0.type == PumpEventStored.EventType.bolus.rawValue }
        #expect(bolusEvents.count == 3, "Three bolus events")
        let extDate = iso8601.date(from: "2025-04-17T10:00:00.000Z")!
        let nonExtDate = iso8601.date(from: "2025-04-17T10:01:00.000Z")!
        let smbDate = iso8601.date(from: "2025-04-17T10:02:00.000Z")!

        // external bolus
        #expect(
            bolusEvents.contains {
                abs($0.timestamp!.timeIntervalSince(extDate)) < 0.001 &&
                    $0.bolus?.amount == NSDecimalNumber(value: 1.0) &&
                    $0.bolus?.isExternal == true &&
                    $0.bolus?.isSMB == false
            },
            "External bolus (1.0 U) at 10:00"
        )
        // non‑external
        #expect(
            bolusEvents.contains {
                abs($0.timestamp!.timeIntervalSince(nonExtDate)) < 0.001 &&
                    $0.bolus?.amount == NSDecimalNumber(value: 2.0) &&
                    $0.bolus?.isExternal == false &&
                    $0.bolus?.isSMB == false
            },
            "Non‑external bolus (2.0 U) at 10:01"
        )
        // SMB
        #expect(
            bolusEvents.contains {
                abs($0.timestamp!.timeIntervalSince(smbDate)) < 0.001 &&
                    $0.bolus?.amount == NSDecimalNumber(value: 3.0) &&
                    $0.bolus?.isExternal == false &&
                    $0.bolus?.isSMB == true
            },
            "SMB bolus (3.0 U) at 10:02"
        )

        // Verify TempBasalDuration + TempBasal
        let durDate = iso8601.date(from: "2025-04-17T10:05:00.000Z")!
        let durEvt = events.first {
            abs($0.timestamp!.timeIntervalSince(durDate)) < 0.001 &&
                $0.tempBasal?.duration == 30 &&
                $0.tempBasal?.rate == NSDecimalNumber(value: 1.5)
        }
        #expect(durEvt != nil, "TempBasalRate at 10:05 for 30 min with rate 1.5 U/h")

        // Verify the four “marker” events
        let markers: [(type: PumpEventStored.EventType, ts: String)] = [
            (.pumpSuspend, "2025-04-17T10:10:00.000Z"),
            (.pumpResume, "2025-04-17T10:15:00.000Z"),
            (.rewind, "2025-04-17T10:20:00.000Z"),
            (.prime, "2025-04-17T10:25:00.000Z")
        ]

        for (eventType, tsString) in markers {
            let date = iso8601.date(from: tsString)!
            #expect(
                events.contains {
                    $0.type == eventType.rawValue &&
                        abs($0.timestamp!.timeIntervalSince(date)) < 0.001
                },
                "\(eventType) at \(tsString)"
            )
        }

        // Ensure file cleaned up and flag set
        let url = documentsURL.appendingPathComponent(OpenAPS.Monitor.pumpHistory)
        #expect(!fileManager.fileExists(atPath: url.path), "Pump JSON should be removed")
        #expect(UserDefaults.standard.bool(forKey: "pumpHistoryImported"))
    }


    @Test("Import carb history with property checks") func testImportCarbHistoryDetails() async throws {
        let carbHistory = [
            CarbsEntry(
                id: "CF9BE626-5B4F-421C-825F-BDEB873FF385",
                createdAt: dateFromISOString("2025-04-17T10:10:00.000Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-17T10:10:00.000Z") ?? Date(),
                carbs: 2,
                fat: 0,
                protein: 0,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: "EF2A99A8-3D96-4F92-8412-2D43C8CF6859"
            ),
            CarbsEntry(
                id: "6FFED023-DE5C-4042-8E4D-D876C37F528C",
                createdAt: dateFromISOString("2025-04-21T21:58:25.452Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-21T21:58:25.452Z") ?? Date(),
                carbs: 2,
                fat: 0,
                protein: 0,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: "EF2A99A8-3D96-4F92-8412-2D43C8CF6859"
            ),
            CarbsEntry(
                id: "32859426-03FC-4CF7-B9A1-16E122C04889",
                createdAt: dateFromISOString("2025-04-21T21:28:25.452Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-21T21:28:25.452Z") ?? Date(),
                carbs: 2,
                fat: 0,
                protein: 0,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: "EF2A99A8-3D96-4F92-8412-2D43C8CF6859"
            ),
            CarbsEntry(
                id: "F9AA11B6-8B2E-4FCA-9E3C-EFE582786CFD",
                createdAt: dateFromISOString("2025-04-21T20:58:25.452Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-21T20:58:25.452Z") ?? Date(),
                carbs: 2,
                fat: 0,
                protein: 0,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: "EF2A99A8-3D96-4F92-8412-2D43C8CF6859"
            ),
            CarbsEntry(
                id: "D2986C75-8EEF-4ACB-AE62-35B5391D437D",
                createdAt: dateFromISOString("2025-04-21T20:28:25.452Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-21T20:28:25.452Z") ?? Date(),
                carbs: 2,
                fat: 0,
                protein: 0,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: "EF2A99A8-3D96-4F92-8412-2D43C8CF6859"
            ),
            CarbsEntry(
                id: "E2F186B2-6A8F-4BC4-A038-3C104F988A78",
                createdAt: dateFromISOString("2025-04-21T19:58:25.452Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-21T19:58:25.452Z") ?? Date(),
                carbs: 2,
                fat: 0,
                protein: 0,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: "EF2A99A8-3D96-4F92-8412-2D43C8CF6859"
            ),
            CarbsEntry(
                id: "EEE7F9A0-490C-4E2B-8F04-ED8A77FC7867",
                createdAt: dateFromISOString("2025-04-21T18:58:25.452Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-21T18:58:25.452Z") ?? Date(),
                carbs: 45,
                fat: 15,
                protein: 25,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: nil
            ),
            CarbsEntry(
                id: "283155A7-5AF0-486E-BD3B-F9F8E2354845",
                createdAt: dateFromISOString("2025-04-21T16:50:02.104Z") ?? Date(),
                actualDate: dateFromISOString("2025-04-21T16:50:02.104Z") ?? Date(),
                carbs: 30,
                fat: 0,
                protein: 0,
                note: "",
                enteredBy: "Trio",
                isFPU: true,
                fpuID: nil
            )
        ]
        
        fileStorage.save(carbHistory, as: OpenAPS.Monitor.carbHistory)

        await importer.importCarbHistoryIfNeeded()

        // Fetch all imported events
        let entries = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: false
        ) as? [CarbEntryStored] ?? []

        #expect(entries.count == 8, "Should import 8 carb entries")
        
        // TODO: add distinct tests

        let url = documentsURL.appendingPathComponent(OpenAPS.Monitor.carbHistory)
        #expect(!fileManager.fileExists(atPath: url.path))
        #expect(UserDefaults.standard.bool(forKey: "carbHistoryImported"))
    }

    @Test("Import glucose history with manual flag checks") func testImportGlucoseHistoryDetails() async throws {
        let glucoseReadings = [
            BloodGlucose(
                _id: "A2BDFCE8-1978-4E12-9B29-BD11DB44A739",
                sgv: 107,
                direction: .flat,
                date: 1733677520950,
                dateString: dateFromISOString("2024-08-23T20:24:07.950Z") ?? Date(),
                unfiltered: 107,
                filtered: nil,
                noise: nil,
                glucose: 107,
                type: "sgv",
                transmitterID: "ABC123"
            ),
            BloodGlucose(
                _id: "A2BDFCE8-1978-4E12-9B29-BD11DB44A739",
                sgv: 112,
                direction: .fortyFiveUp,
                date: 1733676920294,
                dateString: dateFromISOString("2024-12-08T16:55:20.295Z") ?? Date(),
                unfiltered: 112,
                filtered: nil,
                noise: nil,
                glucose: 112,
                type: "sgv",
                transmitterID: "ABC123"
            ),
            BloodGlucose(
                _id: "A2BDFCE8-1978-4E12-9B29-BD11DB44A739",
                sgv: 97,
                direction: .fortyFiveDown,
                date: 1733676620784,
                dateString: dateFromISOString("2024-12-08T16:50:20.784Z") ?? Date(),
                unfiltered: 97,
                filtered: nil,
                noise: nil,
                glucose: 97,
                type: "sgv",
                transmitterID: "ABC123"
            ),
            BloodGlucose(
                _id: "A2BDFCE8-1978-4E12-9B29-BD11DB44A739",
                sgv: 70,
                direction: .doubleDown,
                date: 1733676320525,
                dateString: dateFromISOString("2024-12-08T16:45:20.525Z") ?? Date(),
                unfiltered: 70,
                filtered: nil,
                noise: nil,
                glucose: 70,
                type: "sgv",
                transmitterID: "ABC123"
            ),
            BloodGlucose(
                _id: "A2BDFCE8-1978-4E12-9B29-BD11DB44A739",
                sgv: 188,
                direction: .doubleUp,
                date: 1733676020918,
                dateString: dateFromISOString("2024-12-08T16:40:20.919Z") ?? Date(),
                unfiltered: 188,
                filtered: nil,
                noise: nil,
                glucose: 188,
                type: "sgv",
                transmitterID: "ABC123"
            )
        ]

        // Fetch all GlucoseStored entries sorted by date
        let allReadings = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            key: "date",
            ascending: true
        ) as? [GlucoseStored] ?? []

        #expect(allReadings.count == 5, "Should have imported 5 glucose readings")

        // TODO: add distinct tests
        
        let url = documentsURL.appendingPathComponent(OpenAPS.Monitor.glucose)
        #expect(!fileManager.fileExists(atPath: url.path))
        #expect(UserDefaults.standard.bool(forKey: "glucoseHistoryImported"))
    }

    @Test("Import determination history with nested predBGs and values") func testImportDeterminationHistoryDetails() async throws {
        let iobValues: [Int] = [
            153, 149, 144, 139, 134, 129, 124, 119, 114, 109,
            103,  98,  92,  87,  81,  76,  71,  65,  60,  55,
             50,  44,  39
        ]

        let ztValues: [Int] = [
            153, 147, 140, 134, 128, 121, 115, 109, 104,  98,
             93,  87,  83,  78,  74,  70,  66,  63,  60,  57,
             55,  53,  52,  51,  51,  51,  51,  52,  53,  54,
             56,  58,  60,  62,  65,  67,  70,  73,  76,  78,
             81,  84
        ]

        let uamValues: [Int] = [
            153, 147, 140, 134, 127, 121, 115, 108, 102,  96,
             89,  83,  77,  71,  65,  58,  52,  45,  39
        ]

        let determination = Determination(
            id: UUID(),
            reason: "Autosens ratio: 0.94, ISF: 45→48, COB: 0, Dev: 13, BGI: -6, CR: 7.8→8.3, Target: 85, minPredBG 45, minGuardBG -53, IOBpredBG 39, UAMpredBG 39, TDD: 42.2 U, 89% Bolus 11% Basal, Dynamic ISF/CR: On/On, Logarithmic formula, AF: 0.8, Basal ratio: 1.01; minGuardBG -53<70",
            units: nil,
            insulinReq: Decimal(0),
            eventualBG: 46,
            sensitivityRatio: Decimal(0.9430005356061704),
            rate: Decimal(0),
            duration: Decimal(120),
            iob: Decimal(2.52),
            cob: Decimal(0),
            predictions: Predictions(iob: iobValues, zt: ztValues, cob: nil, uam: uamValues),
            deliverAt:    dateFromISOString("2024-08-01T09:42:08.734Z") ?? Date(),
            carbsReq:     nil,
            temp:         TempType(rawValue: "absolute"),
            bg:           Decimal(153),
            reservoir:    Decimal(3735928559),
            isf:          Decimal(48),
            timestamp:    dateFromISOString("2024-08-01T09:42:09.371Z") ?? Date(),
            current_target: Decimal(85),
            insulinForManualBolus: nil,
            manualBolusErrorString: Decimal(2),
            minDelta:     Decimal(-4.28),
            expectedDelta: Decimal(-4.7),
            minGuardBG:   Decimal(-53),
            minPredBG:    nil,
            threshold:    Decimal(70),
            carbRatio:    Decimal(8.3),
            received:     true
        )
        
        fileStorage.save(determination, as: OpenAPS.Enact.enacted)

        // TODO: add distinct tests

        let url = documentsURL.appendingPathComponent(OpenAPS.Enact.enacted)
        #expect(!fileManager.fileExists(atPath: url.path))
        #expect(UserDefaults.standard.bool(forKey: "enactedHistoryImported"))
    }
}
