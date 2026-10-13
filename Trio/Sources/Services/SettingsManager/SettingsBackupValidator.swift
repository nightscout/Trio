import CoreData
import CryptoKit
import Foundation

extension TrioSettingsBackup {
    static func normalizedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(80))
    }

    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func stableSort<T: Encodable>(_ values: [T]) throws -> [T] {
        try values.map { (try encoded($0), $0) }
            .sorted { $0.0.lexicographicallyPrecedes($1.0) }.map(\.1)
    }

    private static func canonicalStart(_ offset: Int) -> String {
        String(format: "%02d:%02d:00", offset / 60, offset % 60)
    }

    private static func validSchedule(_ starts: [String], _ minutes: [Int]) -> Bool {
        guard minutes.first == 0, Set(minutes).count == minutes.count,
              minutes == minutes.sorted(), starts.count == minutes.count else { return false }
        return zip(starts, minutes).allSatisfy { start, offset in
            guard offset >= 0, offset < 1440 else { return false }
            // Trio's TherapySettingsUtil explicitly accepts both persisted formats.
            return start == canonicalStart(offset) || start == String(canonicalStart(offset).prefix(5))
        }
    }

    static func normalized(_ value: Configuration, preserveDosingMode: Bool = false) throws -> Configuration {
        guard validSchedule(value.basalProfile.map(\.start), value.basalProfile.map(\.minutes)),
              validSchedule(value.carbRatios.schedule.map(\.start), value.carbRatios.schedule.map(\.offset)),
              validSchedule(
                  value.insulinSensitivities.sensitivities.map(\.start),
                  value.insulinSensitivities.sensitivities.map(\.offset)
              ),
              validSchedule(value.glucoseTargets.targets.map(\.start), value.glucoseTargets.targets.map(\.offset))
        else {
            throw BackupError.invalidTherapyConfiguration
        }
        var result = value
        if !preserveDosingMode { result.settings.dosingMode = .open }
        result.settings.cgm = .none
        result.settings.cgmPluginIdentifier = ""
        result.settings.isUploadEnabled = false
        result.settings.isDownloadEnabled = false
        result.settings.useLocalGlucoseSource = false
        result.preferences.timestamp = nil
        result.preferences.bolusIncrement = 0.1
        if var app = result.appConfiguration {
            for index in app.glucoseAlerts.indices { app.glucoseAlerts[index].snoozedUntil = nil }
            result.appConfiguration = app
        }
        result.basalProfile = value.basalProfile
            .map { .init(start: canonicalStart($0.minutes), minutes: $0.minutes, rate: $0.rate) }
        result.carbRatios = .init(units: value.carbRatios.units, schedule: value.carbRatios.schedule.map {
            .init(start: canonicalStart($0.offset), offset: $0.offset, ratio: $0.ratio)
        })
        result.insulinSensitivities = .init(
            units: value.insulinSensitivities.units,
            userPreferredUnits: value.insulinSensitivities.userPreferredUnits,
            sensitivities: value.insulinSensitivities.sensitivities.map {
                .init(sensitivity: $0.sensitivity, offset: $0.offset, start: canonicalStart($0.offset))
            }
        )
        result.glucoseTargets = .init(
            units: value.glucoseTargets.units,
            userPreferredUnits: value.glucoseTargets.userPreferredUnits,
            targets: value.glucoseTargets.targets.map {
                .init(low: $0.low, high: $0.high, start: canonicalStart($0.offset), offset: $0.offset)
            }
        )
        result.presets = Presets(
            overrides: try stableSort(value.presets.overrides.map { preset in
                var result = preset
                // OverrideStorage treats nil and zero as "no target override".
                if result.target == 0 { result.target = nil }
                return result
            }),
            tempTargets: try stableSort(value.presets.tempTargets),
            meals: try stableSort(value.presets.meals)
        )
        return result
    }

    static func fingerprint(for configuration: Configuration) throws -> String {
        try normalizedFingerprint(normalized(configuration))
    }

    static func normalizedFingerprint(_ configuration: Configuration, legacySettings: Bool = false) throws -> String {
        var value = configuration
        if var app = value.appConfiguration {
            // Regenerated alert row IDs must not count as configuration changes.
            let identity = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            for index in app.glucoseAlerts.indices { app.glucoseAlerts[index].id = identity }
            for index in app.deviceAlertConfigurations.indices { app.deviceAlertConfigurations[index].id = identity }
            value.appConfiguration = app
        }
        return try legacySettings ? digest(encoded(LegacyBackupConfiguration(value: value))) : digest(encoded(value))
    }

    static func matchesLegacyFingerprint(_ stored: String?, configuration: Configuration) throws -> Bool {
        guard let stored else { return false }
        var legacy = try normalized(configuration)
        // Older fingerprints included dosing mode; compare each legacy representation.
        for mode in DosingMode.allCases {
            legacy.settings.dosingMode = mode
            if try normalizedFingerprint(legacy, legacySettings: true) == stored { return true }
        }
        return false
    }

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func validated() throws -> TrioSettingsBackup {
        guard (2 ... Self.currentSchema).contains(schemaVersion) else { throw BackupError.unsupportedSchema }
        try Self.validate(configuration)
        try validateHistory()
        // Verify the schema-2 checksum before migration changes the configuration.
        let expected: String
        if schemaVersion == 2 {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            expected = Self.digest(try encoder.encode(LegacyBackupConfiguration(value: configuration)))
        } else if schemaVersion < 5 {
            expected = try Self.normalizedFingerprint(
                Self.normalized(configuration, preserveDosingMode: true),
                legacySettings: true
            )
        } else {
            expected = try Self.fingerprint(for: configuration)
        }
        guard fingerprint == expected else { throw BackupError.integrityCheckFailed }
        if schemaVersion < Self.currentSchema {
            let normalized = try Self.normalized(configuration)
            return TrioSettingsBackup(
                schemaVersion: Self.currentSchema,
                id: id,
                createdAt: createdAt,
                appVersion: appVersion,
                origin: origin,
                name: name,
                configuration: normalized,
                fingerprint: try Self.normalizedFingerprint(normalized),
                dynamicISFHistory: dynamicISFHistory,
                historyChecksum: historyChecksum
            )
        }
        return self
    }

    /// Upload retries may retain a server-side rename, but must match configuration and history.
    func matchesUploadedSnapshot(_ other: Self) throws -> Bool {
        let first = try validated()
        let other = try other.validated()
        return try first.id == other.id && first.createdAt == other.createdAt && first.origin == other.origin &&
            first.appVersion == other.appVersion && first.cloudFingerprint() == other.cloudFingerprint() &&
            first.historyChecksum == other.historyChecksum
    }

    static func contentsEqual(_ first: Data, _ second: Data) throws -> Bool {
        try JSONDecoder().decode(BackupJSONValue.self, from: first) == JSONDecoder().decode(BackupJSONValue.self, from: second)
    }

    static func readBackupData(from url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // Bound the read itself, including files whose size metadata is unavailable.
        let bytes = try file.read(upToCount: maximumSize + 1) ?? Data()
        guard bytes.count <= maximumSize else { throw BackupError.backupTooLarge }
        return bytes
    }

    static func decode(_ bytes: Data, expectedFingerprint: String? = nil) throws -> TrioSettingsBackup {
        guard bytes.count <= maximumSize else { throw BackupError.backupTooLarge }
        let raw = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        guard let schema = raw?["schemaVersion"] as? Int,
              (2 ... currentSchema).contains(schema) else { throw BackupError.unsupportedSchema }
        let snapshot = try JSONDecoder().decode(Self.self, from: bytes)
        // Compare the stored checksum before schema migration changes it.
        if let expectedFingerprint, snapshot.fingerprint != expectedFingerprint { throw BackupError.integrityCheckFailed }
        return try snapshot.validated()
    }

    static func validate(_ value: Configuration) throws {
        func valid(_ value: Decimal) -> Bool { !value.isNaN }
        func positive(_ value: Decimal) -> Bool { valid(value) && value > 0 }
        func nonnegative(_ value: Decimal) -> Bool { valid(value) && value >= 0 }
        func optional(_ value: Decimal?, _ check: (Decimal) -> Bool) -> Bool { value.map(check) ?? true }
        let prefs = value.preferences
        let limits = DecimalPickerSettings()
        guard value.pumpSettings.insulinActionCurve >= limits.dia.min,
              value.pumpSettings.insulinActionCurve <= limits.dia.max,
              value.pumpSettings.maxBolus <= limits.maxBolus.max,
              value.pumpSettings.maxBasal <= limits.maxBasal.max,
              prefs.maxIOB <= limits.maxIOB.max,
              prefs.autosensMax <= limits.autosensMax.max,
              prefs.maxSMBBasalMinutes <= limits.maxSMBBasalMinutes.max,
              prefs.maxUAMSMBBasalMinutes <= limits.maxUAMSMBBasalMinutes.max,
              positive(prefs.min5mCarbimpact),
              prefs.remainingCarbsFraction >= 0, prefs.remainingCarbsFraction <= 1,
              nonnegative(prefs.remainingCarbsCap), nonnegative(prefs.carbsReqThreshold),
              prefs.maxDeltaBGthreshold > 0, prefs.maxDeltaBGthreshold <= 1,
              positive(prefs.noisyCGMTargetMultiplier), positive(prefs.updateInterval),
              positive(value.pumpSettings.insulinActionCurve),
              positive(value.pumpSettings.maxBolus), positive(value.pumpSettings.maxBasal),
              validSchedule(value.basalProfile.map(\.start), value.basalProfile.map(\.minutes)),
              validSchedule(value.carbRatios.schedule.map(\.start), value.carbRatios.schedule.map(\.offset)),
              validSchedule(
                  value.insulinSensitivities.sensitivities.map(\.start),
                  value.insulinSensitivities.sensitivities.map(\.offset)
              ),
              validSchedule(value.glucoseTargets.targets.map(\.start), value.glucoseTargets.targets.map(\.offset)),
              value.carbRatios.units == .grams,
              value.insulinSensitivities.units == .mgdL, value.glucoseTargets.units == .mgdL,
              value.basalProfile.allSatisfy({ nonnegative($0.rate) && $0.rate <= value.pumpSettings.maxBasal }),
              value.carbRatios.schedule.allSatisfy({ positive($0.ratio) }),
              value.insulinSensitivities.sensitivities.allSatisfy({ positive($0.sensitivity) }),
              value.glucoseTargets.targets.allSatisfy({ positive($0.low) && $0.high >= $0.low }),
              positive(value.settings.insulinConcentration),
              positive(value.settings.low), value.settings.high >= value.settings.low,
              nonnegative(prefs.maxIOB), positive(prefs.autosensMin), prefs.autosensMax >= prefs.autosensMin,
              prefs.smbDeliveryRatio >= 0, prefs.smbDeliveryRatio <= 1,
              prefs.weightPercentage >= 0, prefs.weightPercentage <= 1,
              positive(prefs.maxDailySafetyMultiplier), positive(prefs.currentBasalSafetyMultiplier),
              nonnegative(prefs.maxSMBBasalMinutes), nonnegative(prefs.maxUAMSMBBasalMinutes),
              positive(prefs.smbInterval), positive(prefs.insulinPeakTime),
              prefs.insulinPeakTime < value.pumpSettings.insulinActionCurve * 60,
              positive(prefs.adjustmentFactor), positive(prefs.adjustmentFactorSigmoid),
              positive(prefs.halfBasalExerciseTarget), positive(prefs.threshold_setting),
              nonnegative(prefs.maxCOB), positive(prefs.maxMealAbsorptionTime),
              value.presets.overrides.allSatisfy({
                  $0.percentage.isFinite && $0.percentage >= 0 && $0.percentage <= 500 &&
                      optional($0.duration, nonnegative) && optional($0.target, nonnegative) &&
                      optional($0.smbMinutes, nonnegative) && optional($0.uamMinutes, nonnegative) &&
                      optional($0.start, { nonnegative($0) && $0 < 24 }) &&
                      optional($0.end, { nonnegative($0) && $0 < 24 })
              }),
              value.presets.tempTargets.allSatisfy({
                  optional($0.duration, nonnegative) && optional($0.target, positive) &&
                      optional($0.halfBasalTarget, positive)
              }),
              value.presets.meals.allSatisfy({
                  optional($0.carbs, nonnegative) && optional($0.fat, nonnegative) && optional($0.protein, nonnegative)
              }) else { throw BackupError.invalidTherapyConfiguration }
        if let app = value.appConfiguration {
            let times = [app.glucoseAlertConfiguration.dayStart, app.glucoseAlertConfiguration.nightStart]
            guard times.allSatisfy({ (0 ..< 24).contains($0.hour) && (0 ..< 60).contains($0.minute) }),
                  app.glucoseAlerts.allSatisfy({ nonnegative($0.thresholdMgDL) && $0.snoozedUntil == nil }),
                  Set(app.glucoseAlerts.map(\.id)).count == app.glucoseAlerts.count,
                  Set(app.deviceAlertConfigurations.map(\.id)).count == app.deviceAlertConfigurations.count,
                  app.liveActivityOrder?.count ?? 0 <= 4,
                  app.liveActivityOrder?.allSatisfy({ $0.isEmpty || LiveActivityItem(rawValue: $0) != nil }) ?? true
            else { throw BackupError.invalidTherapyConfiguration }
        }
    }
}

/// Reject missing, unknown, or mistyped settings instead of substituting legacy defaults.
struct BackupStrict<Value: Codable>: Decodable {
    let value: Value
    init(from decoder: Decoder) throws {
        let original = try BackupJSONValue(from: decoder)
        value = try Value(from: decoder)
        let encoded = try JSONEncoder().encode(value)
        guard original == (try JSONDecoder().decode(BackupJSONValue.self, from: encoded)) else {
            throw BackupError.invalidTherapyConfiguration
        }
    }
}

indirect enum BackupJSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([Self])
    case object([String: Self])
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Decimal.self) { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([Self].self) { self = .array(decoded) }
        else { self = .object(try value.decode([String: Self].self)) }
    }
}

extension BackupJSONValue {
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case let .bool(item): try value.encode(item)
        case let .number(item): try value.encode(item)
        case let .string(item): try value.encode(item)
        case let .array(items): try value.encode(items)
        case let .object(fields): try value.encode(fields)
        }
    }
}

/// Preserves saved settings and decimal precision while omitting runtime dosing mode.
struct BackupPortableSettings: Codable {
    let value: TrioSettings
    init(value: TrioSettings) { self.value = value }

    init(from decoder: Decoder) throws {
        let original = try BackupJSONValue(from: decoder)
        value = try TrioSettings(from: decoder)
        guard original == (try Self.payload(value)) else { throw BackupError.invalidTherapyConfiguration }
    }

    func encode(to encoder: Encoder) throws { try Self.payload(value).encode(to: encoder) }

    private static func payload(_ settings: TrioSettings) throws -> BackupJSONValue {
        let data = try JSONEncoder().encode(settings)
        guard case var .object(fields) = try JSONDecoder().decode(BackupJSONValue.self, from: data) else {
            throw BackupError.invalidTherapyConfiguration
        }
        fields.removeValue(forKey: "dosingMode")
        return .object(fields)
    }
}
