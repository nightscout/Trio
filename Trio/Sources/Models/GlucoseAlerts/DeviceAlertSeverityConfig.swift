import Foundation

/// User config for one device-alarm severity tier. Applied to every incoming
/// pump / device alert whose category maps to this severity. See
/// `PumpAlertCategory.defaultSeverity` for the mapping table.
struct DeviceAlertSeverityConfig: Codable, Equatable, Identifiable {
    let severity: DeviceAlertSeverity
    var soundFilename: String
    var playsSound: Bool
    /// When true, alarms in this tier bypass Focus Mode / silent switch /
    /// Focus modes (maps to `Alert.InterruptionLevel.critical` and engages the
    /// in-process `CriticalAlertAudioPlayer` fallback if `playsSound` is true).
    /// When false, the alarm uses `.timeSensitive` — banner pierces normal
    /// suppression but obeys silent/DND like any iOS notification.
    var overridesSilenceAndDND: Bool

    var id: String { severity.rawValue }

    init(severity: DeviceAlertSeverity) {
        self.severity = severity
        soundFilename = severity.defaultSoundFilename
        playsSound = true
        overridesSilenceAndDND = severity.defaultOverridesSilenceAndDND
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case severity
        case soundFilename
        case playsSound
        case overridesSilenceAndDND
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decode(DeviceAlertSeverity.self, forKey: .severity)
        soundFilename = try container.decodeIfPresent(String.self, forKey: .soundFilename) ?? severity.defaultSoundFilename
        playsSound = try container.decodeIfPresent(Bool.self, forKey: .playsSound) ?? true
        overridesSilenceAndDND = try container.decodeIfPresent(
            Bool.self,
            forKey: .overridesSilenceAndDND
        ) ?? severity.defaultOverridesSilenceAndDND
    }
}
