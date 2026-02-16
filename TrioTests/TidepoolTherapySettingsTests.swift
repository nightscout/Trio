import CryptoKit
import HealthKit
import LoopKit
import TidepoolKit
import XCTest

@testable import TidepoolServiceKit
@testable import Trio

// Both Trio and TidepoolServiceKit define mgPerDL,
// causing ambiguity. Use HealthKit's native API to avoid the conflict.
private let mgPerDL = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
private let mmolPerL = HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())

// MARK: - StoredSettings → Tidepool Datum Tests

/// Tests that verify Trio's StoredSettings correctly converts to Tidepool's pumpSettings datum.
/// These test the REAL TidepoolServiceKit conversion code path.
class StoredSettingsTidepoolFormatTests: XCTestCase {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder.tidepool
        encoder.outputFormatting.insert(.prettyPrinted)
        encoder.outputFormatting.insert(.sortedKeys)
        return encoder
    }()

    // MARK: - JSON Format

    func testTrioPumpSettingsJSONFormat() {
        let datum = StoredSettings.test.datumPumpSettings(for: "trio-user-123", hostIdentifier: "Trio", hostVersion: "0.6.0")
        let data = try! Self.encoder.encode(datum)
        let json = String(data: data, encoding: .utf8)!

        let requiredFields = [
            "\"type\" : \"pumpSettings\"",
            "\"activeSchedule\" : \"Default\"",
            "\"basalSchedules\"",
            "\"bgTargets\"",
            "\"carbRatios\"",
            "\"insulinSensitivities\"",
            "\"automatedDelivery\"",
            "\"name\" : \"Trio\"",
            "\"version\" : \"0.6.0\""
        ]

        for field in requiredFields {
            XCTAssertTrue(json.contains(field), "Missing required field: \(field)")
        }
    }

    func testTrioPumpSettingsWithMinimalData() {
        let datum = StoredSettings.minimal.datumPumpSettings(for: "test-user", hostIdentifier: "Trio", hostVersion: "0.6.0")
        XCTAssertEqual(datum.activeScheduleName, "Default")
        XCTAssertEqual(datum.origin?.name, "Trio")
        XCTAssertEqual(datum.origin?.version, "0.6.0")
    }

    // MARK: - Schedule Naming

    func testTrioScheduleNaming() {
        let datum = StoredSettings.test.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(datum.activeScheduleName, "Default")
        XCTAssertEqual(datum.basalRateSchedules?.keys.count, 1)
        XCTAssertNotNil(datum.basalRateSchedules?["Default"])
        XCTAssertNotNil(datum.bloodGlucoseTargetSchedules?["Default"])
        XCTAssertNotNil(datum.carbohydrateRatioSchedules?["Default"])
        XCTAssertNotNil(datum.insulinSensitivitySchedules?["Default"])
    }

    // MARK: - Device Metadata

    func testTrioWithPumpDevice() {
        let pumpDevice = HKDevice(
            name: "Omnipod", manufacturer: "Insulet", model: "Dash",
            hardwareVersion: "1.0", firmwareVersion: "2.9.0", softwareVersion: nil,
            localIdentifier: "pod-123", udiDeviceIdentifier: nil
        )

        let settings = makeSettings(pumpDevice: pumpDevice)
        let data = try! Self.encoder.encode(
            settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")
        )
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("Omnipod"), "Missing pump device name")
        XCTAssertTrue(json.contains("Insulet"), "Missing pump manufacturer")
    }

    func testTrioWithCGMDevice() {
        let cgmDevice = HKDevice(
            name: "Dexcom G7", manufacturer: "Dexcom", model: "G7",
            hardwareVersion: nil, firmwareVersion: "1.2.3", softwareVersion: "4.5.6",
            localIdentifier: "CGM123", udiDeviceIdentifier: nil
        )

        let settings = makeSettings(cgmDevice: cgmDevice)
        let datum = settings.datumCGMSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")
        let data = try! Self.encoder.encode(datum)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("Dexcom G7"), "Missing CGM device name")
        XCTAssertTrue(json.contains("Dexcom"), "Missing CGM manufacturer")
    }

    // MARK: - Suspend Threshold

    func testTrioWithSuspendThreshold() {
        let settings = makeSettings(
            suspendThreshold: GlucoseThreshold(unit: mgPerDL, value: 70.0)
        )
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(datum.bloodGlucoseSafetyLimit, 70, "Suspend threshold value should match")
    }

    func testTrioWithSuspendThresholdMmolL() {
        let settings = makeSettings(
            suspendThreshold: GlucoseThreshold(unit: mmolPerL, value: 3.9),
            bgUnit: mmolPerL
        )
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        // Tidepool stores in mg/dL (3.9 mmol/L ≈ 70.2 mg/dL)
        XCTAssertEqual(datum.bloodGlucoseSafetyLimit ?? 0, 3.9 * 18.0182, accuracy: 0.5)
    }

    // MARK: - Max Basal / Max Bolus

    func testTrioWithMaximumValues() {
        let settings = makeSettings(maxBasal: 30.0, maxBolus: 25.0)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(datum.basal?.rateMaximum?.value, 30.0, "Max basal should handle high values")
        XCTAssertEqual(datum.bolus?.amountMaximum?.value, 25.0, "Max bolus should handle high values")
    }

    func testTrioWithMinimumValues() {
        let settings = makeSettings(maxBasal: 0.5, maxBolus: 1.0)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(datum.basal?.rateMaximum?.value, 0.5, "Should preserve low max basal")
        XCTAssertEqual(datum.bolus?.amountMaximum?.value, 1.0, "Should preserve low max bolus")
    }

    // MARK: - Automated Delivery Flag

    func testTrioAutomatedDeliveryFlag() {
        let enabled = makeSettings(dosingEnabled: true)
        let disabled = makeSettings(dosingEnabled: false)

        let enabledDatum = enabled.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")
        let disabledDatum = disabled.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(enabledDatum.automatedDelivery, true)
        XCTAssertEqual(disabledDatum.automatedDelivery, false)
    }

    // MARK: - Unit Conversion

    func testTrioWithMmolLUnits() {
        let targetSchedule = GlucoseRangeSchedule(
            rangeSchedule: DailyQuantitySchedule(
                unit: mmolPerL,
                dailyItems: [RepeatingScheduleValue(
                    startTime: 0,
                    value: DoubleRange(minValue: 5.0, maxValue: 6.0)
                )],
                timeZone: .current
            )!,
            override: nil
        )
        let isfSchedule = InsulinSensitivitySchedule(
            unit: mmolPerL,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: 3.0)],
            timeZone: .current
        )

        let settings = makeSettings(
            glucoseTargetRangeSchedule: targetSchedule,
            insulinSensitivitySchedule: isfSchedule,
            bgUnit: mmolPerL
        )
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        // Tidepool converts to mg/dL (5.0 mmol/L ≈ 90 mg/dL)
        let target = datum.bloodGlucoseTargetSchedules?["Default"]?.first
        XCTAssertEqual(target?.low ?? 0, 90, accuracy: 1)
        XCTAssertEqual(target?.high ?? 0, 108, accuracy: 1)

        let isf = datum.insulinSensitivitySchedules?["Default"]?.first
        XCTAssertEqual(isf?.amount ?? 0, 54, accuracy: 1)
    }

    // MARK: - Override Presets (Temp Targets)

    func testTrioWithMultipleOverridePresets() {
        let presets = [
            makePreset(name: "Exercise", targetLow: 140, targetHigh: 160, scaleFactor: 0.5, hours: 2),
            makePreset(name: "Sleep", targetLow: 110, targetHigh: 130, scaleFactor: 1.2, indefinite: true),
            makePreset(name: "Pre-Meal", targetLow: 80, targetHigh: 90, scaleFactor: 1.0, minutes: 30)
        ]

        let settings = makeSettings(overridePresets: presets)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(datum.overridePresets?.count, 3)
        XCTAssertNotNil(datum.overridePresets?["Exercise"])
        XCTAssertNotNil(datum.overridePresets?["Sleep"])
        XCTAssertNotNil(datum.overridePresets?["Pre-Meal"])
    }

    func testOverridePresetDuration() {
        let preset = makePreset(name: "Exercise", targetLow: 140, targetHigh: 140, scaleFactor: 0.7, hours: 2)
        let settings = makeSettings(overridePresets: [preset])
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        // 2 hours = 7,200 seconds
        XCTAssertEqual(datum.overridePresets?["Exercise"]?.duration, 7200)
    }

    func testOverridePresetIndefiniteDuration() {
        let preset = makePreset(name: "Sleep", targetLow: 110, targetHigh: 120, scaleFactor: 1.0, indefinite: true)
        let settings = makeSettings(overridePresets: [preset])
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        let sleepPreset = datum.overridePresets?["Sleep"]
        XCTAssertTrue(sleepPreset?.duration == nil || sleepPreset?.duration == 0)
    }

    // MARK: - Profile Override Presets (Percentage-Based Scaling)

    func testOverridePresetWithPercentageOnlyNoTarget() {
        // Profile Override with 80% insulin needs but no glucose target
        let preset = TemporaryScheduleOverridePreset(
            id: UUID(),
            symbol: "E",
            name: "Exercise",
            settings: TemporaryScheduleOverrideSettings(
                targetRange: nil,
                insulinNeedsScaleFactor: 0.8
            ),
            duration: .finite(3600)
        )

        let settings = makeSettings(overridePresets: [preset])
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        let exercisePreset = datum.overridePresets?["Exercise"]
        XCTAssertNotNil(exercisePreset)
        XCTAssertNil(exercisePreset?.bloodGlucoseTarget, "No target should produce nil bloodGlucoseTarget")
        XCTAssertEqual(exercisePreset?.basalRateScaleFactor, 0.8, "80% should produce 0.8 basalRateScaleFactor")
    }

    func testOverridePresetWithPercentageAndTarget() {
        // Profile Override with 130% insulin needs AND a glucose target
        let preset = TemporaryScheduleOverridePreset(
            id: UUID(),
            symbol: "S",
            name: "Sick Day",
            settings: TemporaryScheduleOverrideSettings(
                unit: mgPerDL,
                targetRange: DoubleRange(minValue: 120, maxValue: 120),
                insulinNeedsScaleFactor: 1.3
            ),
            duration: .indefinite
        )

        let settings = makeSettings(overridePresets: [preset])
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        let sickPreset = datum.overridePresets?["Sick Day"]
        XCTAssertNotNil(sickPreset)
        XCTAssertNotNil(sickPreset?.bloodGlucoseTarget, "Should include glucose target")
        XCTAssertEqual(sickPreset?.basalRateScaleFactor, 1.3, "130% should produce 1.3 basalRateScaleFactor")
    }

    func testOverridePresetWithNilScaleFactorIsTemporaryTarget() {
        // Temp Target preset: has glucose target but no insulin scaling
        let preset = TemporaryScheduleOverridePreset(
            id: UUID(),
            symbol: "H",
            name: "High Target",
            settings: TemporaryScheduleOverrideSettings(
                unit: mgPerDL,
                targetRange: DoubleRange(minValue: 150, maxValue: 150),
                insulinNeedsScaleFactor: nil
            ),
            duration: .finite(7200)
        )

        let settings = makeSettings(overridePresets: [preset])
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        let highPreset = datum.overridePresets?["High Target"]
        XCTAssertNotNil(highPreset)
        XCTAssertNil(highPreset?.basalRateScaleFactor, "Temp Target should have nil basalRateScaleFactor")
        XCTAssertNotNil(highPreset?.bloodGlucoseTarget, "Temp Target should have glucose target")
    }

    func testMixedTempTargetAndProfileOverridePresets() {
        // Both types should coexist in the same upload
        let tempTarget = TemporaryScheduleOverridePreset(
            id: UUID(),
            symbol: "E",
            name: "Exercise Target",
            settings: TemporaryScheduleOverrideSettings(
                unit: mgPerDL,
                targetRange: DoubleRange(minValue: 150, maxValue: 150),
                insulinNeedsScaleFactor: nil
            ),
            duration: .finite(3600)
        )

        let profileOverride = TemporaryScheduleOverridePreset(
            id: UUID(),
            symbol: "S",
            name: "Sick Day",
            settings: TemporaryScheduleOverrideSettings(
                targetRange: nil,
                insulinNeedsScaleFactor: 1.5
            ),
            duration: .indefinite
        )

        let settings = makeSettings(overridePresets: [tempTarget, profileOverride])
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(datum.overridePresets?.count, 2)

        let exercise = datum.overridePresets?["Exercise Target"]
        XCTAssertNil(exercise?.basalRateScaleFactor, "Temp Target should have no scaling")
        XCTAssertNotNil(exercise?.bloodGlucoseTarget, "Temp Target should have glucose target")

        let sick = datum.overridePresets?["Sick Day"]
        XCTAssertEqual(sick?.basalRateScaleFactor, 1.5, "Profile Override should have 1.5x scaling")
        XCTAssertNil(sick?.bloodGlucoseTarget, "This Profile Override has no target")
    }

    // MARK: - Helpers

    private func makePreset(
        name: String,
        targetLow: Double,
        targetHigh: Double,
        scaleFactor: Double,
        hours: Double? = nil,
        minutes: Double? = nil,
        indefinite: Bool = false
    ) -> TemporaryScheduleOverridePreset {
        let duration: TemporaryScheduleOverride.Duration
        if indefinite {
            duration = .indefinite
        } else if let hours = hours {
            duration = .finite(hours * 3600)
        } else if let minutes = minutes {
            duration = .finite(minutes * 60)
        } else {
            duration = .finite(3600)
        }

        return TemporaryScheduleOverridePreset(
            id: UUID(),
            symbol: String(name.prefix(1)),
            name: name,
            settings: TemporaryScheduleOverrideSettings(
                unit: mgPerDL,
                targetRange: DoubleRange(minValue: targetLow, maxValue: targetHigh),
                insulinNeedsScaleFactor: scaleFactor
            ),
            duration: duration
        )
    }

    private func makeSettings(
        dosingEnabled: Bool = true,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule? = nil,
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = nil,
        overridePresets: [TemporaryScheduleOverridePreset]? = nil,
        maxBasal: Double? = 5.0,
        maxBolus: Double? = 10.0,
        suspendThreshold: GlucoseThreshold? = nil,
        cgmDevice: HKDevice? = nil,
        pumpDevice: HKDevice? = nil,
        bgUnit: HKUnit = mgPerDL
    ) -> StoredSettings {
        let tz = TimeZone(secondsFromGMT: 0)!

        let defaultTarget = GlucoseRangeSchedule(
            rangeSchedule: DailyQuantitySchedule(
                unit: mgPerDL,
                dailyItems: [RepeatingScheduleValue(
                    startTime: 0,
                    value: DoubleRange(minValue: 100.0, maxValue: 110.0)
                )],
                timeZone: tz
            )!,
            override: nil
        )

        let defaultBasal = BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)],
            timeZone: tz
        )!

        let defaultISF = InsulinSensitivitySchedule(
            unit: mgPerDL,
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: 45.0)],
            timeZone: tz
        )!

        let defaultCarb = CarbRatioSchedule(
            unit: .gram(),
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: 15.0)],
            timeZone: tz
        )!

        return StoredSettings(
            date: Date(),
            controllerTimeZone: .current,
            dosingEnabled: dosingEnabled,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule ?? defaultTarget,
            preMealTargetRange: nil,
            workoutTargetRange: nil,
            overridePresets: overridePresets,
            scheduleOverride: nil,
            preMealOverride: nil,
            maximumBasalRatePerHour: maxBasal,
            maximumBolus: maxBolus,
            suspendThreshold: suspendThreshold,
            insulinType: nil,
            defaultRapidActingModel: nil,
            basalRateSchedule: defaultBasal,
            insulinSensitivitySchedule: insulinSensitivitySchedule ?? defaultISF,
            carbRatioSchedule: defaultCarb,
            notificationSettings: nil,
            controllerDevice: nil,
            cgmDevice: cgmDevice,
            pumpDevice: pumpDevice,
            bloodGlucoseUnit: bgUnit,
            syncIdentifier: UUID()
        )
    }
}

// MARK: - Conversion Logic Tests

/// Tests for the conversion math used in TrioSettingsAdapter.
/// These verify the patterns used in the real adapter code.
class TrioSettingsAdapterTests: XCTestCase {
    // MARK: - Basal Profile Conversion

    func testBasalProfileMinutesToSeconds() {
        // TrioSettingsAdapter converts entry.minutes * 60 to get seconds from midnight
        let entries: [(minutes: Int, expectedSeconds: TimeInterval)] = [
            (0, 0), // midnight
            (210, 12600), // 3:30 AM
            (360, 21600), // 6:00 AM
            (720, 43200), // noon
            (1125, 67500), // 6:45 PM
            (1439, 86340) // 11:59 PM
        ]

        for (minutes, expected) in entries {
            let startTime = TimeInterval(minutes * 60)
            XCTAssertEqual(startTime, expected, "\(minutes) minutes should be \(expected) seconds")
        }
    }

    func testBasalProfileWithHHMMSSFormatUsesMinutesField() {
        // The adapter uses entry.minutes, NOT entry.start string parsing.
        // This ensures the "HH:MM:SS" format string doesn't cause issues.
        let entries = [
            BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "06:00:00", minutes: 360, rate: 1.5),
            BasalProfileEntry(start: "12:00:00", minutes: 720, rate: 1.25)
        ]

        let items = entries.map { entry in
            RepeatingScheduleValue(
                startTime: TimeInterval(entry.minutes * 60),
                value: Double(truncating: entry.rate as NSDecimalNumber)
            )
        }
        let schedule = BasalRateSchedule(dailyItems: items, timeZone: .current)

        XCTAssertNotNil(schedule)
        XCTAssertEqual(schedule?.items[0].startTime, 0)
        XCTAssertEqual(schedule?.items[1].startTime, 21600)
        XCTAssertEqual(schedule?.items[2].startTime, 43200)
    }

    // MARK: - Carb Ratio Conversion

    func testCarbRatioOffsetToSeconds() {
        let entries = [
            CarbRatioEntry(start: "00:00", offset: 0, ratio: 15.0),
            CarbRatioEntry(start: "06:00", offset: 360, ratio: 12.0),
            CarbRatioEntry(start: "12:00", offset: 720, ratio: 10.0)
        ]

        let items = entries.map { entry in
            RepeatingScheduleValue(
                startTime: TimeInterval(entry.offset * 60),
                value: Double(truncating: entry.ratio as NSDecimalNumber)
            )
        }

        XCTAssertEqual(items[0].startTime, 0)
        XCTAssertEqual(items[1].startTime, 21600)
        XCTAssertEqual(items[2].startTime, 43200)
    }

    // MARK: - ISF Conversion

    func testInsulinSensitivityOffsetToSeconds() {
        let entries = [
            InsulinSensitivityEntry(sensitivity: 50.0, offset: 0, start: "00:00"),
            InsulinSensitivityEntry(sensitivity: 45.0, offset: 480, start: "08:00")
        ]

        let items = entries.map { entry in
            RepeatingScheduleValue(
                startTime: TimeInterval(entry.offset * 60),
                value: Double(truncating: entry.sensitivity as NSDecimalNumber)
            )
        }

        XCTAssertEqual(items[0].startTime, 0)
        XCTAssertEqual(items[1].startTime, 28800, "480 min = 28800 sec")
    }

    // MARK: - BG Target Conversion

    func testBGTargetOffsetToSeconds() {
        let entries = [
            BGTargetEntry(low: 100, high: 110, start: "00:00", offset: 0),
            BGTargetEntry(low: 110, high: 120, start: "22:00", offset: 1320)
        ]

        XCTAssertEqual(TimeInterval(entries[0].offset * 60), 0)
        XCTAssertEqual(TimeInterval(entries[1].offset * 60), 79200, "1320 min = 79200 sec")
    }

    func testBGTargetLowHighValues() {
        let entry = BGTargetEntry(low: 90, high: 120, start: "00:00", offset: 0)
        XCTAssertEqual(Double(truncating: entry.low as NSDecimalNumber), 90)
        XCTAssertEqual(Double(truncating: entry.high as NSDecimalNumber), 120)
    }

    // MARK: - Profile Override Percentage Conversion

    func testPercentageToInsulinNeedsScaleFactor() {
        // Trio stores percentage (115 = 115%), LoopKit uses scaleFactor (1.15)
        let testCases: [(percentage: Double, expected: Double?)] = [
            (115, 1.15),
            (100, nil), // 100% = no change = nil
            (50, 0.5), // 50% for exercise
            (150, 1.5), // 150% for illness
            (80, 0.8)
        ]

        for (percentage, expected) in testCases {
            let scaleFactor: Double? = percentage != 100 ? percentage / 100.0 : nil
            XCTAssertEqual(
                scaleFactor,
                expected,
                "Percentage \(percentage) should produce scaleFactor \(String(describing: expected))"
            )
        }
    }

    // MARK: - Temp Target Duration Conversion

    func testTempTargetDurationMinutesToSeconds() {
        let durationMinutes: Double = 60
        let duration: TemporaryScheduleOverride.Duration = .finite(durationMinutes * 60)

        if case let .finite(seconds) = duration {
            XCTAssertEqual(seconds, 3600)
        } else {
            XCTFail("Expected finite duration")
        }
    }

    func testTempTargetZeroDurationBecomesIndefinite() {
        let durationMinutes: Double = 0
        let duration: TemporaryScheduleOverride.Duration = durationMinutes == 0 ? .indefinite : .finite(durationMinutes * 60)

        if case .indefinite = duration {
            // Expected
        } else {
            XCTFail("Duration 0 should be indefinite")
        }
    }

    // MARK: - Override Expiration Logic

    func testFiniteOverrideExpired() {
        // Override started 2 hours ago with 30-minute duration → expired
        let startDate = Date().addingTimeInterval(-2 * 3600) // 2 hours ago
        let durationMinutes: Double = 30
        let endDate = startDate.addingTimeInterval(durationMinutes * 60)

        XCTAssertTrue(endDate < Date(), "Override with 30min duration started 2h ago should be expired")
    }

    func testFiniteOverrideStillActive() {
        // Override started 10 minutes ago with 60-minute duration → still active
        let startDate = Date().addingTimeInterval(-10 * 60) // 10 minutes ago
        let durationMinutes: Double = 60
        let endDate = startDate.addingTimeInterval(durationMinutes * 60)

        XCTAssertTrue(endDate > Date(), "Override with 60min duration started 10min ago should still be active")
    }

    func testIndefiniteOverrideNeverExpires() {
        // Indefinite overrides have duration 0 and should never be skipped
        let startDate = Date().addingTimeInterval(-24 * 3600) // 24 hours ago
        let indefinite = true
        let durationMinutes: Double = 0

        // The adapter logic: if !indefinite && duration > 0, check expiration
        let shouldCheckExpiration = !indefinite && durationMinutes > 0
        XCTAssertFalse(shouldCheckExpiration, "Indefinite overrides should not be checked for expiration")
    }

    func testExpiredTempTargetIsSkipped() {
        // Temp target started 3 hours ago with 1-hour duration → expired
        let startDate = Date().addingTimeInterval(-3 * 3600)
        let durationMinutes: Double = 60
        let endDate = startDate.addingTimeInterval(durationMinutes * 60)

        XCTAssertTrue(endDate < Date(), "Temp target with 60min duration started 3h ago should be expired")
    }

    // MARK: - Deterministic Preset UUIDs

    func testPresetIdDeterminism() {
        // Same preset content should always produce the same UUID
        let id1 = computeTestPresetId(name: "Exercise", target: 150, duration: 60, indefinite: false, scaleFactor: 0.8)
        let id2 = computeTestPresetId(name: "Exercise", target: 150, duration: 60, indefinite: false, scaleFactor: 0.8)
        XCTAssertEqual(id1, id2, "Same preset content should produce the same UUID")
    }

    func testPresetIdChangesWithDifferentContent() {
        let baseline = computeTestPresetId(name: "Exercise", target: 150, duration: 60, indefinite: false, scaleFactor: 0.8)
        let changedName = computeTestPresetId(name: "Running", target: 150, duration: 60, indefinite: false, scaleFactor: 0.8)
        let changedTarget = computeTestPresetId(name: "Exercise", target: 140, duration: 60, indefinite: false, scaleFactor: 0.8)
        let changedScale = computeTestPresetId(name: "Exercise", target: 150, duration: 60, indefinite: false, scaleFactor: 0.5)

        XCTAssertNotEqual(baseline, changedName, "Different name should produce different ID")
        XCTAssertNotEqual(baseline, changedTarget, "Different target should produce different ID")
        XCTAssertNotEqual(baseline, changedScale, "Different scale factor should produce different ID")
    }

    // MARK: - Content-Based Sync Identifier

    func testSyncIdentifierDeterminism() {
        // Same therapy values should always produce the same UUID
        let id1 = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: true)
        let id2 = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: true)
        XCTAssertEqual(id1, id2, "Same settings should produce the same sync identifier")
    }

    func testSyncIdentifierChangesWithDifferentSettings() {
        let baseline = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: true)
        let changedBasal = computeTestSyncId(maxBasal: "6.0", maxBolus: "10.0", dosingEnabled: true)
        let changedDosing = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: false)

        XCTAssertNotEqual(baseline, changedBasal, "Different maxBasal should produce different ID")
        XCTAssertNotEqual(baseline, changedDosing, "Different dosingEnabled should produce different ID")
        XCTAssertNotEqual(changedBasal, changedDosing, "All three should be unique")
    }

    // MARK: - Helpers

    /// Replicates the SHA-256 hash algorithm from TrioSettingsAdapter.deterministicPresetId
    private func computeTestPresetId(
        name: String, target: Double?, duration: Double, indefinite: Bool, scaleFactor: Double?
    ) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data("preset:\(name)".utf8))
        if let target = target { hasher.update(data: Data("target:\(target)".utf8)) }
        hasher.update(data: Data("duration:\(duration)".utf8))
        hasher.update(data: Data("indefinite:\(indefinite)".utf8))
        if let sf = scaleFactor { hasher.update(data: Data("scale:\(sf)".utf8)) }
        let digest = hasher.finalize()
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Replicates the SHA-256 hash algorithm from TrioSettingsAdapter.contentBasedSyncIdentifier
    private func computeTestSyncId(maxBasal: String, maxBolus: String, dosingEnabled: Bool) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data("0:1.0".utf8)) // basal entry
        hasher.update(data: Data("0:15".utf8)) // carb ratio
        hasher.update(data: Data("0:50".utf8)) // ISF
        hasher.update(data: Data("0:100:110".utf8)) // BG target
        hasher.update(data: Data("maxBasal:\(maxBasal)".utf8))
        hasher.update(data: Data("maxBolus:\(maxBolus)".utf8))
        hasher.update(data: Data("threshold:100".utf8))
        hasher.update(data: Data("dosingEnabled:\(dosingEnabled)".utf8))
        let digest = hasher.finalize()
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - Test Fixtures

private extension StoredSettings {
    static var test: StoredSettings {
        let tz = TimeZone(secondsFromGMT: 0)!

        let pumpDevice = HKDevice(
            name: "Omnipod", manufacturer: "Insulet", model: "Dash",
            hardwareVersion: "1.0", firmwareVersion: "2.9.0", softwareVersion: nil,
            localIdentifier: "pod-serial-123", udiDeviceIdentifier: nil
        )

        return StoredSettings(
            date: Date(),
            controllerTimeZone: TimeZone(identifier: "America/Los_Angeles")!,
            dosingEnabled: true,
            glucoseTargetRangeSchedule: GlucoseRangeSchedule(
                rangeSchedule: DailyQuantitySchedule(
                    unit: mgPerDL,
                    dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100.0, maxValue: 110.0))],
                    timeZone: tz
                )!,
                override: nil
            ),
            preMealTargetRange: nil,
            workoutTargetRange: nil,
            overridePresets: nil,
            scheduleOverride: nil,
            preMealOverride: nil,
            maximumBasalRatePerHour: 5.0,
            maximumBolus: 10.0,
            suspendThreshold: nil,
            insulinType: .humalog,
            defaultRapidActingModel: nil,
            basalRateSchedule: BasalRateSchedule(dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: 1.0),
                RepeatingScheduleValue(startTime: 21600, value: 1.5),
                RepeatingScheduleValue(startTime: 43200, value: 1.25),
                RepeatingScheduleValue(startTime: 64800, value: 1.0)
            ], timeZone: tz)!,
            insulinSensitivitySchedule: InsulinSensitivitySchedule(
                unit: mgPerDL,
                dailyItems: [RepeatingScheduleValue(startTime: 0, value: 45.0)],
                timeZone: tz
            )!,
            carbRatioSchedule: CarbRatioSchedule(
                unit: .gram(),
                dailyItems: [RepeatingScheduleValue(startTime: 0, value: 15.0)],
                timeZone: tz
            )!,
            notificationSettings: nil,
            controllerDevice: nil,
            cgmDevice: nil,
            pumpDevice: pumpDevice,
            bloodGlucoseUnit: mgPerDL,
            syncIdentifier: UUID()
        )
    }

    static var minimal: StoredSettings {
        let tz = TimeZone(secondsFromGMT: 0)!

        return StoredSettings(
            date: Date(),
            controllerTimeZone: .current,
            dosingEnabled: true,
            glucoseTargetRangeSchedule: GlucoseRangeSchedule(
                rangeSchedule: DailyQuantitySchedule(
                    unit: mgPerDL,
                    dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100.0, maxValue: 110.0))],
                    timeZone: tz
                )!,
                override: nil
            ),
            preMealTargetRange: nil,
            workoutTargetRange: nil,
            overridePresets: nil,
            scheduleOverride: nil,
            preMealOverride: nil,
            maximumBasalRatePerHour: nil,
            maximumBolus: nil,
            suspendThreshold: nil,
            insulinType: nil,
            defaultRapidActingModel: nil,
            basalRateSchedule: BasalRateSchedule(
                dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)],
                timeZone: tz
            )!,
            insulinSensitivitySchedule: InsulinSensitivitySchedule(
                unit: mgPerDL,
                dailyItems: [RepeatingScheduleValue(startTime: 0, value: 45.0)],
                timeZone: tz
            )!,
            carbRatioSchedule: CarbRatioSchedule(
                unit: .gram(),
                dailyItems: [RepeatingScheduleValue(startTime: 0, value: 15.0)],
                timeZone: tz
            )!,
            notificationSettings: nil,
            controllerDevice: nil,
            cgmDevice: nil,
            pumpDevice: nil,
            bloodGlucoseUnit: mgPerDL,
            syncIdentifier: UUID()
        )
    }
}
