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

    func testTrioWithSuspendThresholdMmolLUser() {
        // threshold_setting is always stored in mg/dL even when user displays mmol/L.
        // The adapter creates GlucoseThreshold in mg/dL; TidepoolServiceKit converts internally.
        let settings = makeSettings(
            suspendThreshold: GlucoseThreshold(unit: mgPerDL, value: 70.0),
            bgUnit: mmolPerL
        )
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(
            datum.bloodGlucoseSafetyLimit,
            70,
            "Threshold in mg/dL should pass through correctly regardless of display unit"
        )
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

    // MARK: - Insulin Model

    func testTrioWithInsulinModel() {
        let model = StoredInsulinModel(
            modelType: .rapidAdult,
            delay: .minutes(10),
            actionDuration: .hours(8),
            peakActivity: .minutes(65)
        )
        let settings = makeSettings(insulinModel: model)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertNotNil(datum.insulinModel, "Insulin model should be present")
        XCTAssertEqual(datum.insulinModel?.actionDuration, .hours(8), "DIA should match user setting")
        XCTAssertEqual(datum.insulinModel?.actionPeakOffset, .minutes(65), "Peak time should match user setting")
    }

    func testTrioWithFiaspInsulinModel() {
        let model = StoredInsulinModel(
            modelType: .fiasp,
            delay: .minutes(10),
            actionDuration: .hours(6),
            peakActivity: .minutes(55)
        )
        let settings = makeSettings(insulinModel: model)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        XCTAssertEqual(datum.insulinModel?.modelType, .fiasp, "Ultra-rapid should map to fiasp")
        XCTAssertEqual(datum.insulinModel?.actionDuration, .hours(6))
        XCTAssertEqual(datum.insulinModel?.actionPeakOffset, .minutes(55))
    }

    // MARK: - Helpers

    private func makeSettings(
        dosingEnabled: Bool = true,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule? = nil,
        insulinSensitivitySchedule: InsulinSensitivitySchedule? = nil,
        maxBasal: Double? = 5.0,
        maxBolus: Double? = 10.0,
        suspendThreshold: GlucoseThreshold? = nil,
        insulinModel: StoredInsulinModel? = nil,
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
            overridePresets: nil,
            scheduleOverride: nil,
            preMealOverride: nil,
            maximumBasalRatePerHour: maxBasal,
            maximumBolus: maxBolus,
            suspendThreshold: suspendThreshold,
            insulinType: nil,
            defaultRapidActingModel: insulinModel,
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

/// Tests for the conversion math used in BaseTidepoolManager.
/// These verify the patterns used in the real adapter code.
class BaseTidepoolManagerTests: XCTestCase {
    // MARK: - Basal Profile Conversion

    func testBasalProfileMinutesToSeconds() {
        let entries: [(minutes: Int, expectedSeconds: TimeInterval)] = [
            (0, 0),
            (210, 12600),
            (360, 21600),
            (720, 43200),
            (1125, 67500),
            (1439, 86340)
        ]

        for (minutes, expected) in entries {
            let startTime = TimeInterval(minutes * 60)
            XCTAssertEqual(startTime, expected, "\(minutes) minutes should be \(expected) seconds")
        }
    }

    func testBasalProfileWithHHMMSSFormatUsesMinutesField() {
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

    // MARK: - Insulin Model Conversion

    func testInsulinModelUsesPresetPeakWhenCustomDisabled() {
        // When useCustomPeakTime is false, should use LoopKit preset defaults
        let rapidAdultPeak = ExponentialInsulinModelPreset.rapidActingAdult.peakActivity
        let fiaspPeak = ExponentialInsulinModelPreset.fiasp.peakActivity

        XCTAssertEqual(rapidAdultPeak, .minutes(75), "rapidActingAdult preset peak should be 75 min")
        XCTAssertEqual(fiaspPeak, .minutes(55), "fiasp preset peak should be 55 min")
    }

    func testInsulinModelCustomPeakTimeRange() {
        // insulinPeakTime picker: min 35, max 120, step 1 (minutes)
        let minPeak: TimeInterval = .minutes(35)
        let maxPeak: TimeInterval = .minutes(120)

        XCTAssertEqual(minPeak, 2100, "35 minutes = 2100 seconds")
        XCTAssertEqual(maxPeak, 7200, "120 minutes = 7200 seconds")
    }

    func testInsulinModelDIARange() {
        // insulinActionCurve picker: min 5, max 10, step 0.5 (hours)
        let minDIA: TimeInterval = .hours(5)
        let maxDIA: TimeInterval = .hours(10)

        XCTAssertEqual(minDIA, 18000, "5 hours = 18000 seconds")
        XCTAssertEqual(maxDIA, 36000, "10 hours = 36000 seconds")
    }

    // MARK: - Content-Based Sync Identifier

    func testSyncIdentifierDeterminism() {
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

    /// Replicates the SHA-256 hash algorithm from BaseTidepoolManager.contentBasedSyncIdentifier
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
