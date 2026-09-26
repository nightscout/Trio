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
            return String(localized: "ISF", comment: "")
        case .sensRatio:
            return String(localized: "Sens Ratio", comment: "")
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
            return String(localized: "TBR", comment: "")
        case .eventualBG:
            return String(localized: "evBG", comment: "")
        }
    }
}

// MARK: - Garmin Watchface Setting

/// Defines the available Garmin watchfaces with their associated UUIDs.
enum GarminWatchface: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case trio
    case swissalpine
    /// Not a watchface but a Connect IQ watch app that republishes the payload as
    /// complications, so any watchface with complication slots can show Trio data.
    /// It takes the watchface slot because someone on complications is by definition
    /// not running one of the Trio watchfaces, which leaves that slot free.
    case complication

    var displayName: String {
        switch self {
        case .trio:
            return String(localized: "Trio", comment: "")
        case .swissalpine:
            return String(localized: "Swissalpine", comment: "")
        case .complication:
            return String(localized: "Complication", comment: "")
        }
    }

    /// The UUID for the watchface applications in Garmin Connect IQ
    var watchfaceUUID: UUID? {
        switch self {
        case .trio:
            // return UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")  // local build
            // return UUID(uuidString: "81204522-B1BE-4E19-8E6E-C4032AAF8C6D") // ConnectIQ test build
            return UUID(uuidString: "7a121867-140e-41ba-9982-2e82e2aa6579") // ConnectIQ live build
        case .swissalpine:
            // return UUID(uuidString: "5A643C13-D5A7-40D4-B809-84789FDF4A1F") // ConnectIQ test build
            return UUID(uuidString: "4cea4efd-4aaf-4db4-8891-ef36dde14303") // ConnectIQ live build
        case .complication:
            // return UUID(uuidString: "a897ce34-1135-4632-b855-1c75f1ec27bf") // ConnectIQ beta build
            return UUID(uuidString: "0986fd19-604b-4bcb-a931-6f8621738682") // ConnectIQ live build
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
            return String(localized: "Trio", comment: "")
        case .swissalpine:
            return String(localized: "Swissalpine", comment: "")
        case .none:
            return String(localized: "None", comment: "")
        }
    }

    /// The UUID for the datafield application in Garmin Connect IQ
    var datafieldUUID: UUID? {
        switch self {
        case .trio:
            // return UUID(uuidString: "71cf0982-ca41-42a5-8441-ea81d36056c3")  // local build
            // return UUID(uuidString: "f07f4ef9-108b-4397-95c9-217b5173412e")  // ConnectIQ test build
            return UUID(uuidString: "3d9b6528-8c84-459a-bbab-989b5f001ebd") // ConnectIQ live build
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
    /// Master switch for state-changing watch commands; status and preset reads ignore it.
    var isCommandControlEnabled: Bool = false
    /// Allows bolus and meal+bolus commands; only effective while `isCommandControlEnabled` is on.
    var isBolusCommandEnabled: Bool = false
}

extension GarminWatchSettings {
    /// Keys missing from settings written by older versions keep their defaults, so commands stay off.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let watchface = try? container.decode(GarminWatchface.self, forKey: .watchface) {
            self.watchface = watchface
        }
        if let datafield = try? container.decode(GarminDatafield.self, forKey: .datafield) {
            self.datafield = datafield
        }
        if let primaryAttributeChoice = try? container
            .decode(GarminPrimaryAttributeChoice.self, forKey: .primaryAttributeChoice)
        {
            self.primaryAttributeChoice = primaryAttributeChoice
        }
        if let secondaryAttributeChoice = try? container.decode(
            GarminSecondaryAttributeChoice.self,
            forKey: .secondaryAttributeChoice
        ) {
            self.secondaryAttributeChoice = secondaryAttributeChoice
        }
        if let isWatchfaceDataEnabled = try? container.decode(Bool.self, forKey: .isWatchfaceDataEnabled) {
            self.isWatchfaceDataEnabled = isWatchfaceDataEnabled
        }
        if let isCommandControlEnabled = try? container.decode(Bool.self, forKey: .isCommandControlEnabled) {
            self.isCommandControlEnabled = isCommandControlEnabled
        }
        if let isBolusCommandEnabled = try? container.decode(Bool.self, forKey: .isBolusCommandEnabled) {
            self.isBolusCommandEnabled = isBolusCommandEnabled
        }
    }
}
