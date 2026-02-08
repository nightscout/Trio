import CoreData
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

    private let coreDataContext: NSManagedObjectContext

    init(resolver: Resolver, coreDataContext: NSManagedObjectContext? = nil) {
        self.coreDataContext = coreDataContext ?? CoreDataStack.shared.newTaskContext()
        injectServices(resolver)
    }

    /// Creates a StoredSettings object from current Trio settings
    /// - Parameter cgmDevice: Optional CGM device info (pass from FetchGlucoseManager to avoid circular dependency)
    func createStoredSettings(cgmDevice: HKDevice? = nil) -> StoredSettings? {
        // Load all therapy settings from JSON files
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

        // Use settingsManager for pump settings (has fallback defaults if JSON decode fails)
        let pumpSettings = settingsManager.pumpSettings

        // Load preferences for suspend threshold
        let preferences: Preferences? = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)

        // Convert to LoopKit schedules
        let basalRateSchedule = convertBasalProfile(basalProfile)
        let carbRatioSchedule = convertCarbRatios(carbRatios)
        let insulinSensitivitySchedule = convertInsulinSensitivities(insulinSensitivities)
        let glucoseTargetRangeSchedule = convertBGTargets(bgTargets)

        // Get pump device info
        let pumpDevice = apsManager.pumpManager?.status.device

        // Note: cgmDevice is passed as parameter to avoid circular dependency
        // (TidepoolManager → TrioSettingsAdapter → FetchGlucoseManager → TidepoolManager)

        // Get blood glucose unit
        let bgUnit: HKUnit = settingsManager.settings.units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter

        // Get suspend threshold from preferences
        let suspendThreshold: GlucoseThreshold? = preferences.map { prefs in
            let thresholdValue = Double(truncating: prefs.threshold_setting as NSDecimalNumber)
            return GlucoseThreshold(unit: bgUnit, value: thresholdValue)
        }

        // Get override presets
        let overridePresets = convertOverridePresets()

        // Get active schedule override (Profile Override takes precedence over Temp Target)
        let scheduleOverride = convertActiveProfileOverride(bgUnit: bgUnit)
            ?? convertActiveTempTarget(bgUnit: bgUnit)

        // Create StoredSettings
        return StoredSettings(
            date: Date(),
            controllerTimeZone: TimeZone.current,
            dosingEnabled: settingsManager.settings.closedLoop,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
            preMealTargetRange: nil, // Trio doesn't have a separate pre-meal target
            workoutTargetRange: nil, // Trio doesn't have a separate workout target
            overridePresets: overridePresets,
            scheduleOverride: scheduleOverride,
            preMealOverride: nil,
            maximumBasalRatePerHour: Double(truncating: pumpSettings.maxBasal as NSDecimalNumber),
            maximumBolus: Double(truncating: pumpSettings.maxBolus as NSDecimalNumber),
            suspendThreshold: suspendThreshold,
            insulinType: apsManager.pumpManager?.status.insulinType,
            defaultRapidActingModel: convertInsulinModel(preferences: preferences),
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
                dosingEnabled: settingsManager.settings.closedLoop,
                scheduleOverride: scheduleOverride
            )
        )
    }

    // MARK: - Conversion Methods

    private func convertBasalProfile(_ entries: [BasalProfileEntry]) -> BasalRateSchedule? {
        let items = entries.map { entry in
            // Use minutes field (offset from midnight in minutes) converted to seconds
            let startTime = TimeInterval(entry.minutes * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(truncating: entry.rate as NSDecimalNumber))
        }

        return BasalRateSchedule(dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertCarbRatios(_ carbRatios: CarbRatios) -> CarbRatioSchedule? {
        let items = carbRatios.schedule.map { entry in
            // offset is in minutes from midnight
            let startTime = TimeInterval(entry.offset * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(truncating: entry.ratio as NSDecimalNumber))
        }

        return CarbRatioSchedule(unit: .gram(), dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertInsulinSensitivities(_ sensitivities: InsulinSensitivities) -> InsulinSensitivitySchedule? {
        let unit: HKUnit = sensitivities.units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter

        let items = sensitivities.sensitivities.map { entry in
            // offset is in minutes from midnight
            let startTime = TimeInterval(entry.offset * 60)
            return RepeatingScheduleValue(startTime: startTime, value: Double(truncating: entry.sensitivity as NSDecimalNumber))
        }

        return InsulinSensitivitySchedule(unit: unit, dailyItems: items, timeZone: TimeZone.current)
    }

    private func convertBGTargets(_ bgTargets: BGTargets) -> GlucoseRangeSchedule? {
        let unit: HKUnit = bgTargets.units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter

        let items = bgTargets.targets.map { entry in
            // offset is in minutes from midnight
            let startTime = TimeInterval(entry.offset * 60)
            let minValue = Double(truncating: entry.low as NSDecimalNumber)
            let maxValue = Double(truncating: entry.high as NSDecimalNumber)
            return RepeatingScheduleValue(startTime: startTime, value: DoubleRange(minValue: minValue, maxValue: maxValue))
        }

        let schedule = DailyQuantitySchedule(unit: unit, dailyItems: items, timeZone: TimeZone.current)
        return schedule.map { GlucoseRangeSchedule(rangeSchedule: $0) }
    }

    /// Holds extracted values from Core Data for override/temp target presets (thread-safe).
    struct PresetData {
        let name: String
        let target: Double?
        let duration: Double
        let indefinite: Bool
        let insulinNeedsScaleFactor: Double?
    }

    private func convertOverridePresets() -> [TemporaryScheduleOverridePreset]? {
        var presetDataList: [PresetData] = []

        coreDataContext.performAndWait {
            // Fetch Temp Target presets (glucose target only, no insulin scaling)
            let tempTargetRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            tempTargetRequest.predicate = NSPredicate.allTempTargetPresets
            tempTargetRequest.sortDescriptors = [NSSortDescriptor(key: "orderPosition", ascending: true)]

            do {
                let presets = try coreDataContext.fetch(tempTargetRequest)
                for preset in presets {
                    guard let target = preset.target?.doubleValue else { continue }
                    presetDataList.append(PresetData(
                        name: preset.name ?? "Temp Target",
                        target: target,
                        duration: preset.duration?.doubleValue ?? 0,
                        indefinite: false,
                        insulinNeedsScaleFactor: nil
                    ))
                }
            } catch {
                debug(.service, "Failed to fetch temp target presets from Core Data: \(error)")
            }

            // Fetch Profile Override presets (percentage-based insulin scaling, optional target)
            let overrideRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            overrideRequest.predicate = NSPredicate.allOverridePresets
            overrideRequest.sortDescriptors = [NSSortDescriptor(key: "orderPosition", ascending: true)]

            do {
                let presets = try coreDataContext.fetch(overrideRequest)
                for preset in presets {
                    let target: Double? = {
                        guard let t = preset.target?.doubleValue, t > 0 else { return nil }
                        return t
                    }()
                    let scaleFactor: Double? = preset.percentage != 100 ? preset.percentage / 100.0 : nil

                    presetDataList.append(PresetData(
                        name: preset.name ?? "Override",
                        target: target,
                        duration: preset.duration?.doubleValue ?? 0,
                        indefinite: preset.indefinite,
                        insulinNeedsScaleFactor: scaleFactor
                    ))
                }
            } catch {
                debug(.service, "Failed to fetch profile override presets from Core Data: \(error)")
            }
        }

        guard !presetDataList.isEmpty else {
            return nil
        }

        // Convert to LoopKit format (outside Core Data context, using extracted values)
        let bgUnit: HKUnit = settingsManager.settings.units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter

        return presetDataList.map { presetData -> TemporaryScheduleOverridePreset in
            let targetRange: ClosedRange<HKQuantity>? = presetData.target.map { target in
                let targetQuantity = HKQuantity(unit: bgUnit, doubleValue: target)
                return targetQuantity ... targetQuantity
            }

            let settings = TemporaryScheduleOverrideSettings(
                targetRange: targetRange,
                insulinNeedsScaleFactor: presetData.insulinNeedsScaleFactor
            )

            let duration: TemporaryScheduleOverride.Duration = (presetData.indefinite || presetData.duration == 0)
                ? .indefinite
                : .finite(presetData.duration * 60)

            return TemporaryScheduleOverridePreset(
                id: deterministicPresetId(presetData),
                symbol: String(presetData.name.prefix(1).uppercased()),
                name: presetData.name,
                settings: settings,
                duration: duration
            )
        }
    }

    /// Generates a deterministic UUID for a preset based on its content.
    /// This ensures the same preset always gets the same ID across uploads,
    /// allowing Tidepool to deduplicate rather than creating new presets each time.
    private func deterministicPresetId(_ preset: PresetData) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data("preset:\(preset.name)".utf8))
        if let target = preset.target { hasher.update(data: Data("target:\(target)".utf8)) }
        hasher.update(data: Data("duration:\(preset.duration)".utf8))
        hasher.update(data: Data("indefinite:\(preset.indefinite)".utf8))
        if let sf = preset.insulinNeedsScaleFactor { hasher.update(data: Data("scale:\(sf)".utf8)) }
        let digest = hasher.finalize()
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Converts the currently active Profile Override to a TemporaryScheduleOverride
    /// Profile Overrides can affect ISF, CR, and have a percentage-based insulin needs scale factor
    private func convertActiveProfileOverride(bgUnit: HKUnit) -> TemporaryScheduleOverride? {
        // Struct to hold extracted values from Core Data (thread-safe)
        struct OverrideData {
            let percentage: Double
            let target: Double?
            let startDate: Date
            let duration: Double // in minutes
            let indefinite: Bool
            let id: String
        }

        var overrideData: OverrideData?

        coreDataContext.performAndWait {
            let fetchRequest: NSFetchRequest<OverrideStored> = OverrideStored.fetchRequest()
            fetchRequest.predicate = NSPredicate.lastActiveOverride
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            fetchRequest.fetchLimit = 1

            do {
                guard let override = try coreDataContext.fetch(fetchRequest).first,
                      let startDate = override.date else { return }

                let target: Double? = {
                    guard let t = override.target?.doubleValue, t > 0 else { return nil }
                    return t
                }()

                overrideData = OverrideData(
                    percentage: override.percentage,
                    target: target,
                    startDate: startDate,
                    duration: override.duration?.doubleValue ?? 0,
                    indefinite: override.indefinite,
                    id: override.id ?? UUID().uuidString
                )
            } catch {
                debug(.service, "Failed to fetch active profile override from Core Data: \(error)")
            }
        }

        guard let data = overrideData else { return nil }

        // Skip expired finite overrides
        if !data.indefinite, data.duration > 0 {
            let endDate = data.startDate.addingTimeInterval(data.duration * 60)
            guard endDate > Date() else { return nil }
        }

        // Build target range if override has a target
        let targetRange: ClosedRange<HKQuantity>? = data.target.map { target in
            let quantity = HKQuantity(unit: bgUnit, doubleValue: target)
            return quantity ... quantity
        }

        // Convert percentage to insulin needs scale factor
        // Trio: percentage of 115 means 115% insulin needs
        // LoopKit: insulinNeedsScaleFactor of 1.15 means 115% insulin needs
        let insulinNeedsScaleFactor: Double? = data.percentage != 100 ? data.percentage / 100.0 : nil

        let settings = TemporaryScheduleOverrideSettings(
            targetRange: targetRange,
            insulinNeedsScaleFactor: insulinNeedsScaleFactor
        )

        let duration: TemporaryScheduleOverride.Duration = data.indefinite
            ? .indefinite
            : .finite(data.duration * 60) // Convert minutes to seconds

        return TemporaryScheduleOverride(
            context: .custom,
            settings: settings,
            startDate: data.startDate,
            duration: duration,
            enactTrigger: .local,
            syncIdentifier: UUID(uuidString: data.id) ?? UUID()
        )
    }

    /// Converts the currently active Temp Target to a TemporaryScheduleOverride
    /// Temp Targets only modify the glucose target, without affecting insulin delivery rates
    private func convertActiveTempTarget(bgUnit: HKUnit) -> TemporaryScheduleOverride? {
        // Struct to hold extracted values from Core Data (thread-safe)
        struct TempTargetData {
            let target: Double
            let startDate: Date
            let duration: Double // in minutes
            let id: UUID
        }

        var tempTargetData: TempTargetData?

        coreDataContext.performAndWait {
            let fetchRequest: NSFetchRequest<TempTargetStored> = TempTargetStored.fetchRequest()
            fetchRequest.predicate = NSPredicate.lastActiveTempTarget
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            fetchRequest.fetchLimit = 1

            do {
                guard let tempTarget = try coreDataContext.fetch(fetchRequest).first,
                      let target = tempTarget.target?.doubleValue,
                      let startDate = tempTarget.date else { return }

                tempTargetData = TempTargetData(
                    target: target,
                    startDate: startDate,
                    duration: tempTarget.duration?.doubleValue ?? 0,
                    id: tempTarget.id ?? UUID()
                )
            } catch {
                debug(.service, "Failed to fetch active temp target from Core Data: \(error)")
            }
        }

        guard let data = tempTargetData else { return nil }

        // Skip expired finite temp targets
        if data.duration > 0 {
            let endDate = data.startDate.addingTimeInterval(data.duration * 60)
            guard endDate > Date() else { return nil }
        }

        let targetQuantity = HKQuantity(unit: bgUnit, doubleValue: data.target)
        let targetRange = targetQuantity ... targetQuantity

        let settings = TemporaryScheduleOverrideSettings(
            targetRange: targetRange,
            insulinNeedsScaleFactor: nil // Temp targets don't affect insulin delivery rates
        )

        let duration: TemporaryScheduleOverride.Duration = data.duration == 0
            ? .indefinite
            : .finite(data.duration * 60) // Convert minutes to seconds

        return TemporaryScheduleOverride(
            context: .custom,
            settings: settings,
            startDate: data.startDate,
            duration: duration,
            enactTrigger: .local,
            syncIdentifier: data.id
        )
    }

    private func convertInsulinModel(preferences: Preferences?) -> StoredInsulinModel? {
        guard let curve = preferences?.curve else { return nil }

        let modelType: StoredInsulinModel.ModelType
        switch curve {
        case .rapidActing:
            modelType = .rapidAdult
        case .ultraRapid:
            modelType = .fiasp
        case .bilinear:
            modelType = .rapidAdult // Use rapidAdult as closest approximation
        }

        // Use default timing parameters for the model type
        return StoredInsulinModel(
            modelType: modelType,
            delay: .minutes(10),
            actionDuration: .hours(6),
            peakActivity: .hours(modelType == .fiasp ? 2.5 : 3)
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
        dosingEnabled: Bool,
        scheduleOverride: TemporaryScheduleOverride? = nil
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

        if let override = scheduleOverride {
            hasher.update(data: Data("override:\(override.syncIdentifier)".utf8))
        }

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
