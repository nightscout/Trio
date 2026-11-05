import CoreData
import Foundation
import Testing

@testable import Trio

@Suite("Adjustment Describer Tests", .serialized) struct AdjustmentDescriberTests {
    let context: NSManagedObjectContext
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let describer = AdjustmentDescriber(
        units: .mgdL,
        maxSMBBasalMinutes: 30,
        maxUAMSMBBasalMinutes: 30,
        settingHalfBasalTarget: 160,
        autosensMax: 1.2,
        isExerciseModeActive: false,
        highTTraisesSens: false,
        lowTTlowersSens: false
    )

    init() async throws {
        context = try await CoreDataStack.createForTests().newTaskContext()
    }

    // MARK: - Remaining time

    @Test("Remaining minutes count down from the start") func testRemainingMinutes() {
        let start = now.addingTimeInterval(-10 * 60)
        #expect(AdjustmentDescriber.remainingMinutes(start: start, durationMinutes: NSDecimalNumber(value: 30), now: now) == 20)
    }

    @Test("Remaining minutes never go below zero") func testRemainingMinutesFloor() {
        let start = now.addingTimeInterval(-90 * 60)
        #expect(AdjustmentDescriber.remainingMinutes(start: start, durationMinutes: NSDecimalNumber(value: 30), now: now) == 0)
    }

    @Test("An indefinite override never expires") func testIndefiniteOverrideNeverExpires() async {
        await context.perform {
            let row = makeOverride(start: now.addingTimeInterval(-48 * 60 * 60), duration: 30, indefinite: true)
            #expect(!AdjustmentDescriber.isExpired(row, now: now))
        }
    }

    @Test("A timed override expires at its end") func testTimedOverrideExpires() async {
        await context.perform {
            let running = makeOverride(start: now.addingTimeInterval(-10 * 60), duration: 30)
            let ended = makeOverride(start: now.addingTimeInterval(-31 * 60), duration: 30)
            #expect(!AdjustmentDescriber.isExpired(running, now: now))
            #expect(AdjustmentDescriber.isExpired(ended, now: now))
        }
    }

    @Test("A temp target expires at its end") func testTempTargetExpires() async {
        await context.perform {
            let running = makeTempTarget(start: now.addingTimeInterval(-10 * 60), duration: 30, target: 120)
            let ended = makeTempTarget(start: now.addingTimeInterval(-31 * 60), duration: 30, target: 120)
            #expect(!AdjustmentDescriber.isExpired(running, now: now))
            #expect(AdjustmentDescriber.isExpired(ended, now: now))
        }
    }

    // MARK: - Names

    @Test("A missing name falls back to the generic label") func testNameFallback() async {
        await context.perform {
            let override = makeOverride(start: now, duration: 30)
            let tempTarget = makeTempTarget(start: now, duration: 30, target: 120)
            override.name = nil
            tempTarget.name = nil
            #expect(AdjustmentDescriber.name(of: override) == String(localized: "Custom Override"))
            #expect(AdjustmentDescriber.name(of: tempTarget) == String(localized: "Temp Target"))
            #expect(AdjustmentDescriber.name(of: nil as OverrideStored?) == String(localized: "Custom Override"))
        }
    }

    // MARK: - Override details

    @Test("Override details list time left, percentage and target") func testOverrideDetails() async {
        await context.perform {
            let row = makeOverride(start: now.addingTimeInterval(-30 * 60), duration: 60, percentage: 80, target: 120)
            let expected = "\(formatHrMin(30)), 80 %, \(Decimal(120).formatted(withUnits: .mgdL))"
            #expect(describer.overrideDetails(row, showsTarget: true, now: now) == expected)
        }
    }

    @Test("Override details leave out the target while a temp target runs") func testOverrideDetailsHideTarget() async {
        await context.perform {
            let row = makeOverride(start: now.addingTimeInterval(-30 * 60), duration: 60, percentage: 80, target: 120)
            #expect(describer.overrideDetails(row, showsTarget: false, now: now) == "\(formatHrMin(30)), 80 %")
        }
    }

    @Test("Override details show SMBs off") func testOverrideDetailsSMBOff() async {
        await context.perform {
            let row = makeOverride(start: now, duration: 0, indefinite: true)
            row.smbIsOff = true
            #expect(describer.overrideDetails(row, showsTarget: true, now: now) == String(localized: "SMBs Off\("")"))
        }
    }

    @Test("An override equal to the profile has no details") func testOverrideDetailsEmpty() async {
        await context.perform {
            let row = makeOverride(start: now, duration: 0, indefinite: true)
            #expect(describer.overrideDetails(row, showsTarget: true, now: now) == nil)
        }
    }

    // MARK: - Temp target details

    @Test("Temp target details list target and time left") func testTempTargetDetails() async {
        await context.perform {
            let row = makeTempTarget(start: now.addingTimeInterval(-20 * 60), duration: 60, target: 120)
            let expected = "\(Decimal(120).formatted(withUnits: .mgdL)), 40 min"
            #expect(describer.tempTargetDetails(row, now: now) == expected)
        }
    }

    @Test("Temp target details use the display units") func testTempTargetDetailsMmol() async {
        let mmolDescriber = AdjustmentDescriber(
            units: .mmolL,
            maxSMBBasalMinutes: 30,
            maxUAMSMBBasalMinutes: 30,
            settingHalfBasalTarget: 160,
            autosensMax: 1.2,
            isExerciseModeActive: false,
            highTTraisesSens: false,
            lowTTlowersSens: false
        )
        await context.perform {
            let row = makeTempTarget(start: now.addingTimeInterval(-20 * 60), duration: 60, target: 120)
            let expected = "\(Decimal(120).formatted(withUnits: .mmolL)), 40 min"
            #expect(mmolDescriber.tempTargetDetails(row, now: now) == expected)
        }
    }

    // MARK: - Helpers

    /// Call on the context queue.
    private func makeOverride(
        start: Date,
        duration: Decimal,
        indefinite: Bool = false,
        percentage: Double = 100,
        target: Decimal = 0
    ) -> OverrideStored {
        let row = OverrideStored(context: context)
        row.id = UUID().uuidString
        row.name = "Override"
        row.enabled = true
        row.date = start
        row.duration = NSDecimalNumber(decimal: duration)
        row.indefinite = indefinite
        row.percentage = percentage
        row.target = NSDecimalNumber(decimal: target)
        return row
    }

    /// Call on the context queue.
    private func makeTempTarget(start: Date, duration: Decimal, target: Decimal) -> TempTargetStored {
        let row = TempTargetStored(context: context)
        row.id = UUID()
        row.name = "Temp Target"
        row.enabled = true
        row.date = start
        row.duration = NSDecimalNumber(decimal: duration)
        row.target = NSDecimalNumber(decimal: target)
        return row
    }
}
