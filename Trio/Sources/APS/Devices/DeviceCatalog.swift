// The *UI modules are imported for the CGMManagerUI/PumpManagerUI conformances they declare; without them the
// manager types in this file are not usable as picker entries.
import AccuChekKit
import CGMBLEKit
import CGMBLEKitUI
import DanaKit
import EversenseKit
import Foundation
import G7SensorKit
import G7SensorKitUI
import LibreLoop
import LibreLoopUI
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import MachO
import MedtrumKit
import MinimedKit
import MinimedKitUI
import MockKit
import MockKitUI
import ObjectiveC
import OmnipodKit
import UIKit

/// Single source of truth for every CGM and pump Trio can pair with.
///
/// Loop discovers this metadata at runtime from plugin bundle `Info.plist` keys. Trio statically links every
/// kit, so the metadata lives here instead. Adding a device means adding one entry to this file.
///
/// This is intentionally a plain `enum` with no `Resolver` dependency: `BasePluginManager` and
/// `BaseDeviceDataManager` both read it during `injectServices`, so it must not itself be `Injectable`.
enum DeviceCatalog {}

// MARK: - Manufacturer

/// Section grouping for the device picker.
enum DeviceManufacturer: CaseIterable {
    case abbott
    case dexcom
    case insulet
    case medtronic
    case medtrum
    case roche
    case senseonics
    case sooil
    case otherSources
    case simulator

    /// Brand names are deliberately not localized; only the two synthetic groups are.
    var displayName: String {
        switch self {
        case .abbott: return "Abbott"
        case .dexcom: return "Dexcom"
        case .insulet: return "Insulet"
        case .medtronic: return "Medtronic"
        case .medtrum: return "Medtrum"
        case .roche: return "Roche"
        case .senseonics: return "Senseonics"
        case .sooil: return "SOOIL"
        case .otherSources: return String(localized: "Other Sources", comment: "Device picker section for data relays")
        case .simulator: return String(localized: "Simulator", comment: "Device picker section for simulated devices")
        }
    }

    /// Real hardware sorts alphabetically first, then relays, then simulators.
    var sortRank: Int {
        switch self {
        case .otherSources: return 1
        case .simulator: return 2
        default: return 0
        }
    }
}

// MARK: - Icon

/// Where a catalog entry's artwork comes from.
///
/// Trio embeds every device kit as a framework, so it can load the artwork the kits already ship without any
/// submodule changes — Loop needs `DeviceManagerUI.pickerImage` added inside each kit only because it sees
/// plugins as opaque bundles from the outside.
enum DeviceIcon: Hashable {
    /// Asset in the same framework as the device's manager, so the bundle is derived from the manager type.
    case managerBundle(asset: String)

    /// Asset in a separate `*UI` framework. Those expose no public class to anchor `Bundle(for:)`, so the
    /// bundle identifier is spelled out; `DeviceCatalogTests` pins every one of these.
    case uiBundle(identifier: String, asset: String)

    /// Asset in Trio's own catalog.
    case trio(asset: String)

    /// No artwork available; the row falls back to its category glyph.
    case none

    func image(managerBundle: Bundle?) -> UIImage? {
        switch self {
        case let .managerBundle(asset):
            guard let managerBundle else { return nil }
            return UIImage(named: asset, in: managerBundle, compatibleWith: nil)
        case let .uiBundle(identifier, asset):
            guard let bundle = Bundle(identifier: identifier) else { return nil }
            return UIImage(named: asset, in: bundle, compatibleWith: nil)
        case let .trio(asset):
            return UIImage(named: asset)
        case .none:
            return nil
        }
    }
}

/// Basal-rate limits a pump accepts, used to bound the onboarding basal picker.
///
/// Derived from the kit's own `onboardingSupportedBasalRates` rather than hardcoded. Each kit declares that as a
/// static specifically so it can be read before a pump is paired, which is exactly onboarding's situation.
struct BasalRateCapability: Hashable {
    let minimum: Decimal
    let maximum: Decimal
    let step: Decimal

    init(minimum: Decimal, maximum: Decimal, step: Decimal) {
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
    }

    /// `supportedRates` is the kit's declared grid.
    ///
    /// Zero is dropped even when the pump supports it. oref rejects a schedule whose rate is 0 — see
    /// `Basal.swift` (`lastRateIsValid`, `basalLookup`) and `ProfileError.invalidCurrentBasal` /
    /// `.invalidMaxDailyBasal`, both "must be > 0" — so offering it would let onboarding build a profile the
    /// algorithm then refuses.
    init(supportedRates: [Double]) {
        let sorted = supportedRates.filter { $0 > 0 }.sorted()
        guard let first = sorted.first, let last = sorted.last, sorted.count > 1 else {
            self.init(minimum: 0, maximum: 0, step: 0)
            return
        }
        // Smallest gap in the grid. All four onboarding grids are uniform; DeviceCatalogTests asserts that, so a
        // kit switching to a non-uniform onboarding grid fails loudly rather than silently coarsening the picker.
        let smallestGap = zip(sorted, sorted.dropFirst()).map { $1 - $0 }.min() ?? 0
        self.init(
            minimum: Self.decimal(first),
            maximum: Self.decimal(last),
            step: Self.decimal(smallestGap)
        )
    }

    /// Rounds via string to avoid binary-floating-point artefacts leaking into a user-facing picker.
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.4f", value)) ?? 0
    }

    /// True when the grid is evenly spaced, i.e. representable by a single picker step.
    static func isUniform(_ supportedRates: [Double]) -> Bool {
        let sorted = supportedRates.sorted()
        guard sorted.count > 2 else { return true }
        let gaps = zip(sorted, sorted.dropFirst()).map { ($1 - $0 * 1).rounded(toPlaces: 4) }
        return Set(gaps).count == 1
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - Entry protocol

/// Display metadata shared by CGM and pump entries so one picker view can render both.
protocol DeviceCatalogEntry: Identifiable, Hashable {
    var id: String { get }
    var manufacturer: DeviceManufacturer { get }
    /// Bold first line, e.g. "Omnipod".
    var name: String { get }
    /// Secondary line, e.g. ["Classic", "DASH", "5"]. Empty collapses the row to one line.
    var supportedModels: [String] { get }
    /// Where this device's artwork lives.
    var icon: DeviceIcon { get }
    /// Resolved artwork, or nil to fall back to `fallbackSymbolName`.
    var iconImage: UIImage? { get }
    var fallbackSymbolName: String { get }
    /// False for the CGM `.none` entry, which `listOfCGM` needs but the picker must never offer.
    var isSelectableInPicker: Bool { get }
}

extension DeviceCatalogEntry {
    /// Comma-joined model list for the picker sub-line and the settings hint text.
    var supportedModelsLine: String? {
        supportedModels.isEmpty ? nil : supportedModels.joined(separator: ", ")
    }

    var hintLine: String {
        guard let models = supportedModelsLine else { return name }
        return "\(name) (\(models))"
    }
}

// MARK: - CGM entries

struct CGMCatalogEntry: DeviceCatalogEntry {
    /// Trio drives CGMs two ways: LoopKit manager types, and its own non-LoopKit glucose sources.
    enum Source: Hashable {
        /// Backed by a `CGMType` case other than `.plugin`.
        case native(CGMType)
        /// Backed by a statically linked `CGMManagerUI`; persisted as `CGMType.plugin`.
        case managed(CGMManagerUI.Type)

        /// The value persisted to `TrioSettings.cgm`.
        var cgmType: CGMType {
            switch self {
            case let .native(type): return type
            case .managed: return .plugin
            }
        }

        /// The value persisted to `TrioSettings.cgmPluginIdentifier` for managed sources.
        var id: String {
            switch self {
            case let .native(type): return type.rawValue
            case let .managed(manager): return manager.pluginIdentifier
            }
        }

        var managerType: CGMManagerUI.Type? {
            guard case let .managed(manager) = self else { return nil }
            return manager
        }

        static func == (lhs: Source, rhs: Source) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    let source: Source
    let manufacturer: DeviceManufacturer
    private let rawName: String?
    let supportedModels: [String]
    let icon: DeviceIcon

    var id: String { source.id }
    var cgmType: CGMType { source.cgmType }
    var managerType: CGMManagerUI.Type? { source.managerType }

    /// Localized names must be computed, not stored: a `String(localized:)` baked into a `static let` resolves
    /// once per process and would not follow an in-session language change.
    var name: String { rawName ?? source.cgmType.displayName }

    /// Manager-backed sources have no meaningful `CGMType.subtitle` (they all share `.plugin`), so they fall
    /// back to their own name, matching what `BasePluginManager` produced before.
    var subtitle: String {
        if let models = supportedModelsLine { return models }
        return source.managerType == nil ? source.cgmType.subtitle : name
    }

    var iconImage: UIImage? {
        icon.image(managerBundle: source.managerType.map { Bundle(for: $0) })
    }

    var fallbackSymbolName: String { "sensor.tag.radiowaves.forward" }
    var isSelectableInPicker: Bool { source.cgmType != .none }

    init(
        _ source: Source,
        manufacturer: DeviceManufacturer,
        name: String? = nil,
        supportedModels: [String] = [],
        icon: DeviceIcon = .none
    ) {
        self.source = source
        self.manufacturer = manufacturer
        rawName = name
        self.supportedModels = supportedModels
        self.icon = icon
    }
}

// MARK: - Pump entries

struct PumpCatalogEntry: DeviceCatalogEntry {
    let manager: PumpManagerUI.Type
    let manufacturer: DeviceManufacturer
    let name: String
    let supportedModels: [String]
    let icon: DeviceIcon

    /// Identifiers written by older managers that this entry now handles.
    ///
    /// Omnipod carries "Omni" so that pump state persisted by the retired OmniKit ("Omnipod") and OmniBLE
    /// ("Omnipod-DASH") managers still resolves to the universal OmnipodKit manager.
    let legacyIdentifierPrefixes: [String]

    let allowedInsulinTypes: [InsulinType]

    /// Bounds for the onboarding basal-rate picker.
    let basalCapability: BasalRateCapability

    /// Whether the pump reports a reservoir rewind. Tubed pumps do; patch pumps have nothing to rewind, so
    /// `rewindResetsAutosens` is meaningless for them and onboarding hides the question.
    let reportsRewindEvents: Bool

    var id: String { manager.pluginIdentifier }
    var iconImage: UIImage? { icon.image(managerBundle: Bundle(for: manager)) }
    var fallbackSymbolName: String { "ivfluid.bag" }
    var isSelectableInPicker: Bool { true }

    init(
        _ manager: PumpManagerUI.Type,
        manufacturer: DeviceManufacturer,
        name: String,
        supportedModels: [String] = [],
        icon: DeviceIcon = .none,
        legacyIdentifierPrefixes: [String] = [],
        allowedInsulinTypes: [InsulinType] = DeviceCatalog.defaultAllowedInsulinTypes,
        basalCapability: BasalRateCapability,
        reportsRewindEvents: Bool
    ) {
        self.manager = manager
        self.manufacturer = manufacturer
        self.name = name
        self.supportedModels = supportedModels
        self.icon = icon
        self.legacyIdentifierPrefixes = legacyIdentifierPrefixes
        self.allowedInsulinTypes = allowedInsulinTypes
        self.basalCapability = basalCapability
        self.reportsRewindEvents = reportsRewindEvents
    }

    static func == (lhs: PumpCatalogEntry, rhs: PumpCatalogEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - The catalog

extension DeviceCatalog {
    static let defaultAllowedInsulinTypes: [InsulinType] = [.apidra, .humalog, .novolog, .fiasp, .lyumjev]

    /// Order here is the order shown in the picker, within each manufacturer section.
    static let cgms: [CGMCatalogEntry] = [
        CGMCatalogEntry(.native(.none), manufacturer: .otherSources),

        // Both Libre names carry their variants inline, matching the titles the driver authors chose upstream.
        // No icons: LibreTransmitterUI ships no asset catalog, and LibreLoopUI ships only onboarding steps.
        CGMCatalogEntry(
            .managed(LibreTransmitterManagerV3.self),
            manufacturer: .abbott,
            name: "FreeStyle Libre 1 / 2 / 2+"
        ),
        // "(Beta)" stays in the bold first line: it is a maturity warning about a driver feeding dosing
        // decisions, so it must not be demoted to the secondary line.
        CGMCatalogEntry(
            .managed(LibreLoopCGMManager.self),
            manufacturer: .abbott,
            name: "FreeStyle Libre 3 / 3+ (Beta)"
        ),

        // Dexcom rebrands rather than versioning, so the "/" names carry the variants and a sub-line would
        // just repeat them.
        // No G5 icon: CGMBLEKitUI ships only "g6", and reusing it would picture the wrong hardware.
        CGMCatalogEntry(.managed(G5CGMManager.self), manufacturer: .dexcom, name: "Dexcom G5"),
        CGMCatalogEntry(
            .managed(G6CGMManager.self),
            manufacturer: .dexcom,
            name: "Dexcom G6 / ONE",
            icon: .uiBundle(identifier: "com.loopkit.CGMBLEKitUI", asset: "g6")
        ),
        CGMCatalogEntry(
            .managed(G7CGMManager.self),
            manufacturer: .dexcom,
            name: "Dexcom G7 / ONE+",
            icon: .uiBundle(identifier: "org.loopkit.G7SensorKitUI", asset: "g7")
        ),

        CGMCatalogEntry(
            .managed(AccuChekCgmManager.self),
            manufacturer: .roche,
            name: "Accu-Chek SmartGuide",
            icon: .managerBundle(asset: "sensor")
        ),

        CGMCatalogEntry(
            .managed(EversenseCGMManager.self),
            manufacturer: .senseonics,
            name: "Eversense",
            supportedModels: ["E3", "E365"],
            icon: .managerBundle(asset: "transmitter")
        ),

        CGMCatalogEntry(.native(.nightscout), manufacturer: .otherSources, icon: .trio(asset: "owl")),
        CGMCatalogEntry(.native(.xdrip), manufacturer: .otherSources),

        CGMCatalogEntry(
            .native(.simulator),
            manufacturer: .simulator,
            icon: .uiBundle(identifier: "com.loopkit.MockKitUI", asset: "CGM Simulator")
        )
    ]

    static let pumps: [PumpCatalogEntry] = [
        PumpCatalogEntry(
            OmniPumpManager.self,
            manufacturer: .insulet,
            name: "Omnipod",
            supportedModels: ["Classic", "DASH", "5"],
            icon: .managerBundle(asset: "Pod"),
            legacyIdentifierPrefixes: ["Omni"],
            basalCapability: BasalRateCapability(supportedRates: OmniPumpManager.onboardingSupportedBasalRates),
            reportsRewindEvents: false
        ),
        PumpCatalogEntry(
            MinimedPumpManager.self,
            manufacturer: .medtronic,
            name: "MiniMed",
            supportedModels: ["x15", "x22", "x23", "x54"],
            icon: .uiBundle(identifier: "org.loopkit.MinimedKitUI", asset: "5xx Small Outline"),
            basalCapability: BasalRateCapability(supportedRates: MinimedPumpManager.onboardingSupportedBasalRates),
            reportsRewindEvents: true
        ),
        PumpCatalogEntry(
            MedtrumPumpManager.self,
            manufacturer: .medtrum,
            name: "Medtrum Nano",
            supportedModels: ["200U", "300U"],
            icon: .managerBundle(asset: "nano200"),
            basalCapability: BasalRateCapability(supportedRates: MedtrumPumpManager.onboardingSupportedBasalRates),
            reportsRewindEvents: false
        ),
        PumpCatalogEntry(
            DanaKitPumpManager.self,
            manufacturer: .sooil,
            name: "Dana",
            supportedModels: ["DanaRS", "Dana-i"],
            icon: .managerBundle(asset: "danars"),
            basalCapability: BasalRateCapability(supportedRates: DanaKitPumpManager.onboardingSupportedBasalRates),
            reportsRewindEvents: true
        ),
        PumpCatalogEntry(
            MockPumpManager.self,
            manufacturer: .simulator,
            name: String(localized: "Pump Simulator", comment: "Simulated pump in the device picker"),
            icon: .uiBundle(identifier: "com.loopkit.MockKitUI", asset: "Pump Simulator"),
            basalCapability: BasalRateCapability(supportedRates: MockPumpManager.onboardingSupportedBasalRates),
            reportsRewindEvents: false
        )
    ]
}

// MARK: - Lookups

extension DeviceCatalog {
    static let cgmManagerEntries: [CGMCatalogEntry] = cgms.filter { $0.managerType != nil }

    static let pumpManagersByIdentifier: [String: PumpManagerUI.Type] = pumps.reduce(into: [:]) { result, entry in
        result[entry.id] = entry.manager
    }

    /// The list backing the CGM settings screen. Includes `.none`; the picker filters it out.
    static var cgmModels: [CGMModel] {
        cgms.map(CGMModel.init)
    }

    /// Pumps offered during onboarding: real hardware only, since onboarding is configuring actual therapy.
    static var onboardingPumps: [PumpCatalogEntry] {
        pumps.filter { $0.manufacturer != .simulator }
    }

    /// Resolves an already-paired pump to an onboarding-eligible entry.
    ///
    /// Users upgrading from a pre-onboarding Trio already have an instantiated pump manager, so onboarding
    /// preselects it. Anything not offered during onboarding — the simulator, or a driver no longer catalogued —
    /// falls back to the default, which is what the old manager cascade did by only testing the four real pumps.
    static func onboardingPump(forPersistedIdentifier identifier: String) -> PumpCatalogEntry {
        guard let entry = pumpEntry(forPersistedIdentifier: identifier),
              onboardingPumps.contains(entry)
        else {
            return defaultOnboardingPump
        }
        return entry
    }

    /// Onboarding's fallback when no pump is paired yet, and for any pump not offered during onboarding.
    static var defaultOnboardingPump: PumpCatalogEntry {
        // Omnipod has always been this fallback; its basal bounds are the DASH values onboarding assumed.
        pumps.first { $0.manufacturer == .insulet } ?? pumps[0]
    }

    static func cgmEntry(id: String) -> CGMCatalogEntry? {
        cgms.first { $0.id == id }
    }

    static func pumpEntry(id: String) -> PumpCatalogEntry? {
        pumps.first { $0.id == id }
    }

    /// Resolves an identifier read back from persisted pump state, including ones written by retired managers.
    ///
    /// Note the identifier used for alert routing is *not* always this one: `AlertCatalogRegistry` keys MiniMed
    /// entries under "Minimed" while `MinimedPumpManager.pluginIdentifier` is "Minimed500". Do not unify them —
    /// see TrioTests/MinimedKitAlertEmissionTests.swift.
    static func pumpEntry(forPersistedIdentifier identifier: String) -> PumpCatalogEntry? {
        if let exact = pumpEntry(id: identifier) {
            return exact
        }
        return pumps.first { entry in
            entry.legacyIdentifierPrefixes.contains { identifier.hasPrefix($0) }
        }
    }

    /// Groups entries into picker sections, ordered by `sortRank` then manufacturer name.
    static func sections<Entry: DeviceCatalogEntry>(
        for entries: [Entry]
    ) -> [(manufacturer: DeviceManufacturer, entries: [Entry])] {
        Dictionary(grouping: entries.filter(\.isSelectableInPicker), by: \.manufacturer)
            .map { (manufacturer: $0.key, entries: $0.value) }
            .sorted { lhs, rhs in
                (lhs.manufacturer.sortRank, lhs.manufacturer.displayName)
                    < (rhs.manufacturer.sortRank, rhs.manufacturer.displayName)
            }
    }
}
