import Foundation
import Testing
@testable import Trio

class BundleReference {}

@Suite("IoB using real pump history JSON") struct IobJsonTests {
    @Test("should produce the same JSON IobResult as Javascript") func createIobResultFromJson() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        guard let path = testBundle.path(forResource: "pump_history", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let pumpHistory: [PumpHistoryEvent] = try! JSONBridge.from(string: String(data: data, encoding: .utf8)!),
              let path2 = testBundle.path(forResource: "iob_result", ofType: "json"),
              let data2 = try? Data(contentsOf: URL(fileURLWithPath: path2)),
              let iobResultsJson: [IobResult] = try! JSONBridge.from(string: String(data: data2, encoding: .utf8)!)
        else {
            #expect(Bool(false))
            return
        }

        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 0.5)
        ]

        var profile = Profile()
        profile.dia = 10
        profile.basalprofile = basalProfile
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.curve = .ultraRapid

        let clock = Date("2025-02-18T23:23:31.036Z")!

        let iobResult = try IobGenerator.generate(history: pumpHistory, profile: profile, clock: clock, autosens: nil)

        #expect(iobResult.count == iobResultsJson.count)
        for (swift, javascript) in zip(iobResult, iobResultsJson) {
            #expect(swift.approximatelyEquals(javascript))
        }
    }

    @Test("should produce the same JSON history as Javascript") func createIobHistoryFromJson() async throws {
        let testBundle = Bundle(for: BundleReference.self)
        guard let path = testBundle.path(forResource: "pump_history", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let path2 = testBundle.path(forResource: "iob_history", ofType: "json"),
              let data2 = try? Data(contentsOf: URL(fileURLWithPath: path2)),
              let pumpHistory: [PumpHistoryEvent] = try! JSONBridge.from(string: String(data: data, encoding: .utf8)!),
              let iobHistoryJson: [HistoryRecord] = try! JSONBridge.from(string: String(data: data2, encoding: .utf8)!)
        else {
            #expect(Bool(false))
            return
        }

        let basalProfile = [
            BasalProfileEntry(start: "00:00", minutes: 0, rate: 0.5)
        ]

        var profile = Profile()
        profile.dia = 10
        profile.basalprofile = basalProfile
        profile.currentBasal = 1
        profile.maxDailyBasal = 1
        profile.curve = .ultraRapid

        let clock = Date("2025-02-18T23:23:31.036Z")!

        let computedHistory = pumpHistory.map { $0.computedEvent() }

        let history = try IobHistory.calcTempTreatments(
            history: computedHistory,
            profile: profile,
            clock: clock,
            autosens: nil,
            zeroTempDuration: nil
        )

        #expect(history.count == iobHistoryJson.count)
        let historyBolusCount = history.filter({ $0.insulin != nil }).count
        let jsonBolusCount = iobHistoryJson.filter({ record in
            switch record {
            case .insulin: return true
            case .basal: return false
            }
        }).count
        #expect(historyBolusCount == jsonBolusCount)

        let historyBasalCount = history.filter({ $0.rate != nil }).count
        let jsonBasalCount = iobHistoryJson.filter({ record in
            switch record {
            case .insulin: return false
            case .basal: return true
            }
        }).count
        #expect(historyBasalCount == jsonBasalCount)

        let historyInsulin = history.compactMap(\.insulin).reduce(0, +)
        let jsonInsulin = iobHistoryJson.compactMap({ record in
            switch record {
            case let .insulin(r):
                return r.insulin
            case .basal:
                return nil
            }
        }).reduce(0, +)
        #expect(historyInsulin == jsonInsulin)
    }
}
