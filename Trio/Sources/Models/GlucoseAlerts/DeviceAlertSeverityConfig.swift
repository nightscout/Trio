import Foundation

/// One user-configured behavior variant for a device-alarm severity tier.
/// Multiple configs per severity are allowed — each with its own
/// `activeOption` (Day & Night / Day only / Night only) — so the user can
/// e.g. have a Critical config that overrides Silence during the day and
/// a second Critical config that goes silent at night.
///
/// Lookup at fire time picks the variant whose `activeOption` matches the
/// current day/night window, falling back to the `.always` variant.
struct DeviceAlertSeverityConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var severity: DeviceAlertSeverity
    var isEnabled: Bool
    var soundFilename: String
    var playsSound: Bool
    /// When true, alarms in this tier bypass Focus Mode / silent switch
    /// (maps to `Alert.InterruptionLevel.critical` and engages the in-process
    /// `CriticalAlertAudioPlayer` fallback if `playsSound` is true).
    /// When false, the alarm uses `.timeSensitive`.
    var overridesSilenceAndDND: Bool
    var activeOption: ActiveOption

    init(
        id: UUID = UUID(),
        severity: DeviceAlertSeverity,
        activeOption: ActiveOption = .always
    ) {
        self.id = id
        self.severity = severity
        isEnabled = true
        soundFilename = severity.defaultSoundFilename
        playsSound = true
        overridesSilenceAndDND = severity.defaultOverridesSilenceAndDND
        self.activeOption = activeOption
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case severity
        case isEnabled
        case soundFilename
        case playsSound
        case overridesSilenceAndDND
        case activeOption
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        severity = try container.decode(DeviceAlertSeverity.self, forKey: .severity)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        soundFilename = try container.decodeIfPresent(String.self, forKey: .soundFilename) ?? severity.defaultSoundFilename
        playsSound = try container.decodeIfPresent(Bool.self, forKey: .playsSound) ?? true
        overridesSilenceAndDND = try container.decodeIfPresent(
            Bool.self,
            forKey: .overridesSilenceAndDND
        ) ?? severity.defaultOverridesSilenceAndDND
        activeOption = try container.decodeIfPresent(ActiveOption.self, forKey: .activeOption) ?? .always
    }
}
