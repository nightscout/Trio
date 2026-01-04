import Foundation

// MARK: - Garmin Data Type Settings

/// Primary attribute selection for Garmin watchface and datafield.
/// Determines whether to display COB, ISF, or Sensitivity Ratio alongside glucose data.
/// Used by both Trio and SwissAlpine watchfaces.
enum GarminPrimaryAttributeChoice: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case cob
    case isf
    case sensRatio

    var displayName: String {
        switch self {
        case .cob:
            return String(localized: "COB", comment: "")
        case .isf:
            return String(localized: "Insulin Sensitivity Factor", comment: "")
        case .sensRatio:
            return String(localized: "Sensitivity Ratio", comment: "")
        }
    }
}

/// Secondary attribute selection for both Trio and SwissAlpine watchfaces.
/// Determines whether to display Temp Basal Rate or Eventual BG.
enum GarminSecondaryAttributeChoice: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case tbr
    case eventualBG

    var displayName: String {
        switch self {
        case .tbr:
            return String(localized: "TBR (Temp Basal Rate)", comment: "")
        case .eventualBG:
            return String(localized: "Eventual BG", comment: "")
        }
    }
}

// MARK: - Garmin Watchface Setting

/// Defines the available Garmin watchfaces with their associated UUIDs.
enum GarminWatchface: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case trio
    case swissalpine

    var displayName: String {
        switch self {
        case .trio:
            return String(localized: "Trio original", comment: "")
        case .swissalpine:
            return String(localized: "Trio Swissalpine", comment: "")
        }
    }

    /// The UUID for the watchface application in Garmin Connect IQ
    var watchfaceUUID: UUID? {
        switch self {
        case .trio:
            // return UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")  // local build
            // return UUID(uuidString: "81204522-B1BE-4E19-8E6E-C4032AAF8C6D") // ConnectIQ test build
            return UUID(uuidString: "7a121867-140e-41ba-9982-2e82e2aa6579") // ConnectIQ live build
        case .swissalpine:
            // return UUID(uuidString: "5A643C13-D5A7-40D4-B809-84789FDF4A1F") // ConnectIQ test build
            return UUID(uuidString: "4cea4efd-4aaf-4db4-8891-ef36dde14303") // ConnectIQ live build
        }
    }
}

// MARK: - Garmin Datafield Setting

/// Defines the available Garmin datafields with their associated UUIDs.
enum GarminDatafield: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case trio
    case swissalpine
    case none

    var displayName: String {
        switch self {
        case .trio:
            return String(localized: "Trio original", comment: "")
        case .swissalpine:
            return String(localized: "Trio Swissalpine", comment: "")
        case .none:
            return String(localized: "None", comment: "")
        }
    }

    /// The UUID for the datafield application in Garmin Connect IQ
    var datafieldUUID: UUID? {
        switch self {
        case .trio:
            return UUID(uuidString: "71cf0982-ca41-42a5-8441-ea81d36056c3")
        case .swissalpine:
            // return UUID(uuidString: "7A2268F6-3381-4474-81BD-0A3E7F458CB7") // ConnectIQ test build
            return UUID(uuidString: "dec5292a-74b0-41bc-8e45-cd93f1d5e137") // ConnectIQ live build
        case .none:
            return nil
        }
    }
}

// MARK: - Garmin Watch Settings Group

/// Groups related Garmin watch settings together for easier management.
/// Both watchfaces use the same settings: primaryAttributeChoice and secondaryAttributeChoice.
struct GarminWatchSettings: Codable, Hashable {
    var watchface: GarminWatchface = .trio
    var datafield: GarminDatafield = .trio
    var primaryAttributeChoice: GarminPrimaryAttributeChoice = .cob
    var secondaryAttributeChoice: GarminSecondaryAttributeChoice = .tbr
    var isWatchfaceDataEnabled: Bool = false
}
