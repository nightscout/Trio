import CryptoKit
import Foundation
import HealthKit
import LoopKit
import Swinject
import UIKit

/// Converts Trio's JSON-based settings format to LoopKit's StoredSettings format
/// for uploading to Tidepool
final class TrioSettingsAdapter: Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var settingsManager: SettingsManager!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    /// Creates a StoredSettings object from current Trio settings
    /// - Parameter cgmDevice: Optional CGM device info (pass from FetchGlucoseManager to avoid circular dependency)
    func createStoredSettings(cgmDevice: HKDevice? = nil) -> StoredSettings? {
        guard let basalProfile: [BasalProfileEntry] = storage
            .retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
            let carbRatios: CarbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
            let insulinSensitivities: InsulinSensitivities = storage.retrieve(
                OpenAPS.Settings.insulinSensitivities,
                as: InsulinSensitivities.self
            ),
            let bgTargets: BGTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        else {
            debug(.service, "Failed to load Trio therapy settings for Tidepool upload")
            return nil
        }

        let pumpSettings = settingsManager.pumpSettings
        let preferences: Preferences? = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)

        let basalRateSchedule = convertBasalProfile(basalProfile)
        let carbRatioSchedule = convertCarbRatios(carbRatios)
        let insulinSensitivitySchedule = convertInsulinSensitivities(insulinSensitivities)
        let glucoseTargetRangeSchedule = convertBGTargets(bgTargets)

        let pumpDevice = apsManager.pumpManager?.status.device
        let bgUnit: HKUnit = settingsManager.settings.units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter

        // threshold_setting is always stored in mg/dL; TidepoolServiceKit calls
        // convertTo(unit:) internally, so we pass it through in its native unit
        let suspendThreshold: GlucoseThreshold? = preferences.map { prefs in
            let thresholdValue = Double(truncating: prefs.threshold_setting as NSDecimalNumber)
            return GlucoseThreshold(unit: .milligramsPerDeciliter, value: thresholdValue)
        }

        return StoredSettings(
            date: Date(),
            controllerTimeZone: TimeZone.current,
            dosingEnabled: settingsManager.settings.closedLoop,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
            preMealTargetRange: nil,
            workoutTargetRange: nil,
            overridePresets: nil,
            scheduleOverride: nil,
            preMealOverride: nil,
            maximumBasalRatePerHour: Double(truncating: pumpSettings.maxBasal as NSDecimalNumber),
            maximumBolus: Double(truncating: pumpSettings.maxBolus as NSDecimalNumber),
            suspendThreshold: suspendThreshold,
            insulinType: apsManager.pumpManager?.status.insulinType,
            defaultRapidActingModel: convertInsulinModel(preferences: preferences, pumpSettings: pumpSettings),
            basalRateSchedule: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            carbRatioSchedule: carbRatioSchedule,
            notificationSettings: nil,
            controllerDevice: createControllerDevice(),
            cgmDevice: cgmDevice,
            pumpDevice: pumpDevice,
            bloodGlucoseUnit: bgUnit,
            syncIdentifier: contentBasedSyncIdentifier(
                basalProfile: basalProfile,
                carbRatios: carbRatios,
                insulinSensitivities: insulinSensitivities,
                bgTargets: bgTargets,
                pumpSettings: pumpSettings,
                preferences: preferences,
                dosingEnabled: settingsManager.settings.closedLoop
            )
        )
    }

    // MARK: - Conversion Methods

    private func convertBasalProfile(_ entries: [BasalProfileEntry]) -> BasalRateSchedule? {
        let items = entries.map { entry in
            let startTime = TimeInterval(entry.minutes * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(truncating: entry.rate as NSDecimalNumber))
        }

        return BasalRateSchedule(dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertCarbRatios(_ carbRatios: CarbRatios) -> CarbRatioSchedule? {
        let items = carbRatios.schedule.map { entry in
            let startTime = TimeInterval(entry.offset * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(truncating: entry.ratio as NSDecimalNumber))
        }

        return CarbRatioSchedule(unit: .gram(), dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertInsulinSensitivities(_ sensitivities: InsulinSensitivities) -> InsulinSensitivitySchedule? {
        // sensitivities.units comes from the data model itself, not the user's display preference
        let unit: HKUnit = sensitivities.units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter

        let items = sensitivities.sensitivities.map { entry in
            let startTime = TimeInterval(entry.offset * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(truncating: entry.sensitivity as NSDecimalNumber))
        }

        return InsulinSensitivitySchedule(unit: unit, dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertBGTargets(_ bgTargets: BGTargets) -> GlucoseRangeSchedule? {
        // bgTargets.units comes from the data model itself, not the user's display preference
        let unit: HKUnit = bgTargets.units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter

        let items = bgTargets.targets.map { entry in
            let startTime = TimeInterval(entry.offset * 60)
            let minValue = Double(truncating: entry.low as NSDecimalNumber)
            let maxValue = Double(truncating: entry.high as NSDecimalNumber)
            return RepeatingScheduleValue(startTime: startTime, value: DoubleRange(minValue: minValue, maxValue: maxValue))
        }

        let schedule = DailyQuantitySchedule(unit: unit, dailyItems: items, timeZone: TimeZone.current)
        return schedule.map { GlucoseRangeSchedule(rangeSchedule: $0) }
    }

    private func convertInsulinModel(preferences: Preferences?, pumpSettings: PumpSettings) -> StoredInsulinModel? {
        guard let curve = preferences?.curve else { return nil }

        let modelType: StoredInsulinModel.ModelType
        let preset: ExponentialInsulinModelPreset
        switch curve {
        case .bilinear,
             .rapidActing:
            modelType = .rapidAdult
            preset = .rapidActingAdult
        case .ultraRapid:
            // Distinguish Fiasp vs Lyumjev using the pump's configured insulin type
            let isLyumjev = apsManager.pumpManager?.status.insulinType == .lyumjev
            modelType = isLyumjev ? .lyumjev : .fiasp
            preset = isLyumjev ? .lyumjev : .fiasp
        }

        let dia = Double(truncating: pumpSettings.insulinActionCurve as NSDecimalNumber)

        // Use custom peak time if enabled, otherwise fall back to LoopKit preset default
        let peakActivity: TimeInterval
        if let prefs = preferences, prefs.useCustomPeakTime {
            peakActivity = .minutes(Double(truncating: prefs.insulinPeakTime as NSDecimalNumber))
        } else {
            peakActivity = preset.peakActivity
        }

        return StoredInsulinModel(
            modelType: modelType,
            delay: preset.delay,
            actionDuration: .hours(dia),
            peakActivity: peakActivity
        )
    }

    /// Generates a deterministic UUID based on the content of the therapy settings.
    /// If settings haven't changed, the same UUID is produced, enabling Tidepool
    /// server-side deduplication via the origin ID.
    private func contentBasedSyncIdentifier(
        basalProfile: [BasalProfileEntry],
        carbRatios: CarbRatios,
        insulinSensitivities: InsulinSensitivities,
        bgTargets: BGTargets,
        pumpSettings: PumpSettings,
        preferences: Preferences?,
        dosingEnabled: Bool
    ) -> UUID {
        var hasher = SHA256()

        for entry in basalProfile {
            hasher.update(data: Data("\(entry.minutes):\(entry.rate)".utf8))
        }

        for entry in carbRatios.schedule {
            hasher.update(data: Data("\(entry.offset):\(entry.ratio)".utf8))
        }

        for entry in insulinSensitivities.sensitivities {
            hasher.update(data: Data("\(entry.offset):\(entry.sensitivity)".utf8))
        }

        for entry in bgTargets.targets {
            hasher.update(data: Data("\(entry.offset):\(entry.low):\(entry.high)".utf8))
        }

        hasher.update(data: Data("maxBasal:\(pumpSettings.maxBasal)".utf8))
        hasher.update(data: Data("maxBolus:\(pumpSettings.maxBolus)".utf8))

        if let prefs = preferences {
            hasher.update(data: Data("threshold:\(prefs.threshold_setting)".utf8))
        }

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

    private func createControllerDevice() -> StoredSettings.ControllerDevice {
        let device = UIDevice.current
        return StoredSettings.ControllerDevice(
            name: "Trio",
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            model: device.model,
            modelIdentifier: device.modelIdentifier
        )
    }
}

// MARK: - Helper Extensions

private extension UIDevice {
    var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }
}
