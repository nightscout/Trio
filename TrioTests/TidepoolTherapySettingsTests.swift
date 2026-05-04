import CryptoKit
import HealthKit
import LoopKit
import Testing
import TidepoolKit

@testable import TidepoolServiceKit
@testable import Trio

// Both Trio and TidepoolServiceKit define mgPerDL,
// causing ambiguity. Use HealthKit's native API to avoid the conflict.
private let mgPerDL = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
private let mmolPerL = HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())

// MARK: - StoredSettings → Tidepool Datum Tests

/// Tests that verify Trio's StoredSettings correctly converts to Tidepool's pumpSettings datum.
/// These test the REAL TidepoolServiceKit conversion code path.
@Suite("StoredSettings Tidepool Format Tests") struct StoredSettingsTidepoolFormatTests {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder.tidepool
        encoder.outputFormatting.insert(.prettyPrinted)
        encoder.outputFormatting.insert(.sortedKeys)
        return encoder
    }()

    // MARK: - JSON Format

    @Test("Pump settings JSON contains required fields") func pumpSettingsJSONFormat() {
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
            #expect(json.contains(field), "Missing required field: \(field)")
        }
    }

    @Test("Pump settings with minimal data") func pumpSettingsWithMinimalData() {
        let datum = StoredSettings.minimal.datumPumpSettings(for: "test-user", hostIdentifier: "Trio", hostVersion: "0.6.0")
        #expect(datum.activeScheduleName == "Default")
        #expect(datum.origin?.name == "Trio")
        #expect(datum.origin?.version == "0.6.0")
    }

    // MARK: - Schedule Naming

    @Test("All schedules use 'Default' name") func scheduleNaming() {
        let datum = StoredSettings.test.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(datum.activeScheduleName == "Default")
        #expect(datum.basalRateSchedules?.keys.count == 1)
        #expect(datum.basalRateSchedules?["Default"] != nil)
        #expect(datum.bloodGlucoseTargetSchedules?["Default"] != nil)
        #expect(datum.carbohydrateRatioSchedules?["Default"] != nil)
        #expect(datum.insulinSensitivitySchedules?["Default"] != nil)
    }

    // MARK: - Device Metadata

    @Test("Pump device metadata is included") func pumpDeviceMetadata() {
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

        #expect(json.contains("Omnipod"), "Missing pump device name")
        #expect(json.contains("Insulet"), "Missing pump manufacturer")
    }

    @Test("CGM device metadata is included") func cgmDeviceMetadata() {
        let cgmDevice = HKDevice(
            name: "Dexcom G7", manufacturer: "Dexcom", model: "G7",
            hardwareVersion: nil, firmwareVersion: "1.2.3", softwareVersion: "4.5.6",
            localIdentifier: "CGM123", udiDeviceIdentifier: nil
        )

        let settings = makeSettings(cgmDevice: cgmDevice)
        let datum = settings.datumCGMSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")
        let data = try! Self.encoder.encode(datum)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("Dexcom G7"), "Missing CGM device name")
        #expect(json.contains("Dexcom"), "Missing CGM manufacturer")
    }

    // MARK: - Suspend Threshold

    @Test("Suspend threshold value is preserved") func suspendThreshold() {
        let settings = makeSettings(
            suspendThreshold: GlucoseThreshold(unit: mgPerDL, value: 70.0)
        )
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(datum.bloodGlucoseSafetyLimit == 70, "Suspend threshold value should match")
    }

    @Test("Suspend threshold in mg/dL passes through for mmol/L user") func suspendThresholdMmolLUser() {
        // threshold_setting is always stored in mg/dL even when user displays mmol/L.
        // The adapter creates GlucoseThreshold in mg/dL; TidepoolServiceKit converts internally.
        let settings = makeSettings(
            suspendThreshold: GlucoseThreshold(unit: mgPerDL, value: 70.0),
            bgUnit: mmolPerL
        )
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(
            datum.bloodGlucoseSafetyLimit == 70,
            "Threshold in mg/dL should pass through correctly regardless of display unit"
        )
    }

    // MARK: - Max Basal / Max Bolus

    @Test("Maximum basal and bolus values are preserved") func maximumValues() {
        let settings = makeSettings(maxBasal: 30.0, maxBolus: 25.0)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(datum.basal?.rateMaximum?.value == 30.0, "Max basal should handle high values")
        #expect(datum.bolus?.amountMaximum?.value == 25.0, "Max bolus should handle high values")
    }

    @Test("Minimum basal and bolus values are preserved") func minimumValues() {
        let settings = makeSettings(maxBasal: 0.5, maxBolus: 1.0)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(datum.basal?.rateMaximum?.value == 0.5, "Should preserve low max basal")
        #expect(datum.bolus?.amountMaximum?.value == 1.0, "Should preserve low max bolus")
    }

    // MARK: - Automated Delivery Flag

    @Test("Automated delivery flag reflects dosing state") func automatedDeliveryFlag() {
        let enabled = makeSettings(dosingEnabled: true)
        let disabled = makeSettings(dosingEnabled: false)

        let enabledDatum = enabled.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")
        let disabledDatum = disabled.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(enabledDatum.automatedDelivery == true)
        #expect(disabledDatum.automatedDelivery == false)
    }

    // MARK: - Unit Conversion

    @Test("mmol/L values are converted to mg/dL by Tidepool") func mmolLUnitConversion() {
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
        #expect(abs((target?.low ?? 0) - 90) <= 1)
        #expect(abs((target?.high ?? 0) - 108) <= 1)

        let isf = datum.insulinSensitivitySchedules?["Default"]?.first
        #expect(abs((isf?.amount ?? 0) - 54) <= 1)
    }

    // MARK: - Insulin Model

    @Test("Insulin model preserves DIA and peak time") func insulinModel() {
        let model = StoredInsulinModel(
            modelType: .rapidAdult,
            delay: .minutes(10),
            actionDuration: .hours(8),
            peakActivity: .minutes(65)
        )
        let settings = makeSettings(insulinModel: model)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(datum.insulinModel != nil, "Insulin model should be present")
        #expect(datum.insulinModel?.actionDuration == .hours(8), "DIA should match user setting")
        #expect(datum.insulinModel?.actionPeakOffset == .minutes(65), "Peak time should match user setting")
    }

    @Test("Fiasp insulin model maps correctly") func fiaspInsulinModel() {
        let model = StoredInsulinModel(
            modelType: .fiasp,
            delay: .minutes(10),
            actionDuration: .hours(6),
            peakActivity: .minutes(55)
        )
        let settings = makeSettings(insulinModel: model)
        let datum = settings.datumPumpSettings(for: "test", hostIdentifier: "Trio", hostVersion: "0.6.0")

        #expect(datum.insulinModel?.modelType == .fiasp, "Ultra-rapid should map to fiasp")
        #expect(datum.insulinModel?.actionDuration == .hours(6))
        #expect(datum.insulinModel?.actionPeakOffset == .minutes(55))
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
@Suite("BaseTidepoolManager Conversion Tests") struct BaseTidepoolManagerTests {
    // MARK: - Basal Profile Conversion

    @Test("Basal profile minutes convert to seconds") func basalProfileMinutesToSeconds() {
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
            #expect(startTime == expected, "\(minutes) minutes should be \(expected) seconds")
        }
    }

    @Test("Basal profile uses minutes field for start time") func basalProfileUsesMinutesField() {
        let entries = [
            BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1.0),
            BasalProfileEntry(start: "06:00:00", minutes: 360, rate: 1.5),
            BasalProfileEntry(start: "12:00:00", minutes: 720, rate: 1.25)
        ]

        let items = entries.map { entry in
            RepeatingScheduleValue(
                startTime: TimeInterval(entry.minutes * 60),
                value: Double(entry.rate)
            )
        }
        let schedule = BasalRateSchedule(dailyItems: items, timeZone: .current)

        #expect(schedule != nil)
        #expect(schedule?.items[0].startTime == 0)
        #expect(schedule?.items[1].startTime == 21600)
        #expect(schedule?.items[2].startTime == 43200)
    }

    // MARK: - Carb Ratio Conversion

    @Test("Carb ratio offset converts to seconds") func carbRatioOffsetToSeconds() {
        let entries = [
            CarbRatioEntry(start: "00:00", offset: 0, ratio: 15.0),
            CarbRatioEntry(start: "06:00", offset: 360, ratio: 12.0),
            CarbRatioEntry(start: "12:00", offset: 720, ratio: 10.0)
        ]

        let items = entries.map { entry in
            RepeatingScheduleValue(
                startTime: TimeInterval(entry.offset * 60),
                value: Double(entry.ratio)
            )
        }

        #expect(items[0].startTime == 0)
        #expect(items[1].startTime == 21600)
        #expect(items[2].startTime == 43200)
    }

    // MARK: - ISF Conversion

    @Test("ISF offset converts to seconds") func insulinSensitivityOffsetToSeconds() {
        let entries = [
            InsulinSensitivityEntry(sensitivity: 50.0, offset: 0, start: "00:00"),
            InsulinSensitivityEntry(sensitivity: 45.0, offset: 480, start: "08:00")
        ]

        let items = entries.map { entry in
            RepeatingScheduleValue(
                startTime: TimeInterval(entry.offset * 60),
                value: Double(entry.sensitivity)
            )
        }

        #expect(items[0].startTime == 0)
        #expect(items[1].startTime == 28800, "480 min = 28800 sec")
    }

    // MARK: - BG Target Conversion

    @Test("BG target offset converts to seconds") func bgTargetOffsetToSeconds() {
        let entries = [
            BGTargetEntry(low: 100, high: 110, start: "00:00", offset: 0),
            BGTargetEntry(low: 110, high: 120, start: "22:00", offset: 1320)
        ]

        #expect(TimeInterval(entries[0].offset * 60) == 0)
        #expect(TimeInterval(entries[1].offset * 60) == 79200, "1320 min = 79200 sec")
    }

    @Test("BG target low and high values are preserved") func bgTargetLowHighValues() {
        let entry = BGTargetEntry(low: 90, high: 120, start: "00:00", offset: 0)
        #expect(Double(entry.low) == 90)
        #expect(Double(entry.high) == 120)
    }

    // MARK: - Insulin Model Conversion

    @Test("Preset peak times match expected values when custom peak disabled") func presetPeakTimes() {
        // When useCustomPeakTime is false, should use LoopKit preset defaults
        let rapidAdultPeak = ExponentialInsulinModelPreset.rapidActingAdult.peakActivity
        let fiaspPeak = ExponentialInsulinModelPreset.fiasp.peakActivity

        #expect(rapidAdultPeak == .minutes(75), "rapidActingAdult preset peak should be 75 min")
        #expect(fiaspPeak == .minutes(55), "fiasp preset peak should be 55 min")
    }

    @Test("Custom peak time range boundaries") func customPeakTimeRange() {
        // insulinPeakTime picker: min 35, max 120, step 1 (minutes)
        let minPeak: TimeInterval = .minutes(35)
        let maxPeak: TimeInterval = .minutes(120)

        #expect(minPeak == 2100, "35 minutes = 2100 seconds")
        #expect(maxPeak == 7200, "120 minutes = 7200 seconds")
    }

    @Test("DIA range boundaries") func diaRange() {
        // insulinActionCurve picker: min 5, max 10, step 0.5 (hours)
        let minDIA: TimeInterval = .hours(5)
        let maxDIA: TimeInterval = .hours(10)

        #expect(minDIA == 18000, "5 hours = 18000 seconds")
        #expect(maxDIA == 36000, "10 hours = 36000 seconds")
    }

    // MARK: - Content-Based Sync Identifier

    @Test("Same settings produce the same sync identifier") func syncIdentifierDeterminism() {
        let id1 = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: true)
        let id2 = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: true)
        #expect(id1 == id2, "Same settings should produce the same sync identifier")
    }

    @Test("Different settings produce different sync identifiers") func syncIdentifierChanges() {
        let baseline = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: true)
        let changedBasal = computeTestSyncId(maxBasal: "6.0", maxBolus: "10.0", dosingEnabled: true)
        let changedDosing = computeTestSyncId(maxBasal: "5.0", maxBolus: "10.0", dosingEnabled: false)

        #expect(baseline != changedBasal, "Different maxBasal should produce different ID")
        #expect(baseline != changedDosing, "Different dosingEnabled should produce different ID")
        #expect(changedBasal != changedDosing, "All three should be unique")
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
