import DanaKit
import Foundation
import LoopKitUI
import MachO
import MedtrumKit
import MinimedKit
import ObjectiveC
import OmnipodKit
import Testing
@testable import Trio
import UIKit

@Suite("Device Catalog Tests") struct DeviceCatalogTests {
    // MARK: - Integrity

    @Test("Catalog identifiers are unique") func testIdentifiersAreUnique() {
        let cgmIDs = DeviceCatalog.cgms.map(\.id)
        #expect(Set(cgmIDs).count == cgmIDs.count, "Duplicate CGM identifier in catalog: \(cgmIDs)")

        let pumpIDs = DeviceCatalog.pumps.map(\.id)
        #expect(Set(pumpIDs).count == pumpIDs.count, "Duplicate pump identifier in catalog: \(pumpIDs)")
    }

    @Test("Pump entry ids match their manager's plugin identifier") func testPumpIdentifiersMatchManagers() {
        for entry in DeviceCatalog.pumps {
            #expect(
                entry.id == entry.manager.pluginIdentifier,
                "\(entry.name) id \(entry.id) != \(entry.manager.pluginIdentifier)"
            )
        }
    }

    @Test("Every entry has a display name") func testEntriesHaveNames() {
        for entry in DeviceCatalog.cgms {
            #expect(!entry.name.isEmpty, "CGM \(entry.id) has an empty name")
        }
        for entry in DeviceCatalog.pumps {
            #expect(!entry.name.isEmpty, "Pump \(entry.id) has an empty name")
        }
    }

    // MARK: - Persisted identifier resolution

    @Test("Legacy Omnipod identifiers resolve to the universal Omnipod manager") func testLegacyOmnipodIdentifiers() {
        // OmniKit persisted "Omnipod" and OmniBLE persisted "Omnipod-DASH" before OmnipodKit unified them.
        for identifier in ["Omni", "Omnipod", "Omnipod-DASH"] {
            let entry = DeviceCatalog.pumpEntry(forPersistedIdentifier: identifier)
            #expect(entry?.name == "Omnipod", "\(identifier) should resolve to Omnipod, got \(entry?.name ?? "nil")")
        }
    }

    @Test("MiniMed resolves by its real plugin identifier") func testMinimedIdentifier() {
        // MinimedPumpManager.pluginIdentifier is "Minimed500", not "Minimed".
        #expect(DeviceCatalog.pumpEntry(forPersistedIdentifier: "Minimed500")?.name == "MiniMed")
        #expect(DeviceCatalog.pumpEntry(forPersistedIdentifier: "Minimed") == nil)
    }

    @Test("Unknown identifiers do not resolve") func testUnknownIdentifier() {
        #expect(DeviceCatalog.pumpEntry(forPersistedIdentifier: "NotARealPump") == nil)
    }

    // MARK: - CGM source mapping

    @Test("Managed CGM entries persist as .plugin, native entries persist as themselves") func testCGMSourceMapping() {
        for entry in DeviceCatalog.cgms {
            if entry.managerType != nil {
                #expect(entry.cgmType == .plugin, "\(entry.name) is manager-backed so it must persist as .plugin")
                #expect(entry.id == entry.managerType?.pluginIdentifier)
            } else {
                #expect(entry.cgmType.rawValue == entry.id, "\(entry.name) id must be its CGMType raw value")
            }
        }
    }

    @Test("Every CGMType case is represented in the catalog") func testAllCGMTypesCovered() {
        for type in CGMType.allCases where type != .plugin {
            #expect(
                DeviceCatalog.cgms.contains { $0.cgmType == type },
                "CGMType.\(type.rawValue) is missing from the catalog"
            )
        }
    }

    // MARK: - Picker presentation

    @Test("The 'none' CGM is in the catalog but never offered in the picker") func testNoneIsNotSelectable() {
        #expect(DeviceCatalog.cgms.contains { $0.cgmType == .none }, "listOfCGM needs a .none entry")

        let offered = DeviceCatalog.sections(for: DeviceCatalog.cgms).flatMap(\.entries)
        #expect(!offered.contains { $0.cgmType == .none }, ".none must never render as a picker row")
    }

    @Test("Simulator sections sort last") func testSimulatorSortsLast() {
        let cgmSections = DeviceCatalog.sections(for: DeviceCatalog.cgms)
        #expect(cgmSections.last?.manufacturer == .simulator)

        let pumpSections = DeviceCatalog.sections(for: DeviceCatalog.pumps)
        #expect(pumpSections.last?.manufacturer == .simulator)
    }

    @Test("Data relays sort after hardware but before simulators") func testOtherSourcesRank() {
        #expect(DeviceManufacturer.dexcom.sortRank < DeviceManufacturer.otherSources.sortRank)
        #expect(DeviceManufacturer.otherSources.sortRank < DeviceManufacturer.simulator.sortRank)
    }

    @Test("Sections contain every selectable entry exactly once") func testSectionsArePartition() {
        let selectable = DeviceCatalog.cgms.filter(\.isSelectableInPicker).map(\.id).sorted()
        let sectioned = DeviceCatalog.sections(for: DeviceCatalog.cgms).flatMap(\.entries).map(\.id).sorted()
        #expect(selectable == sectioned)
    }

    // MARK: - Model sub-lines

    @Test("Model sub-lines render as a comma-joined list") func testSupportedModelsLine() {
        let omnipod = DeviceCatalog.pumps.first { $0.name == "Omnipod" }
        #expect(omnipod?.supportedModelsLine == "Classic, DASH, 5")
        #expect(omnipod?.hintLine == "Omnipod (Classic, DASH, 5)")

        let g5 = DeviceCatalog.cgms.first { $0.name == "Dexcom G5" }
        #expect(g5?.supportedModelsLine == nil, "An empty model list must collapse the row to one line")
        #expect(g5?.hintLine == "Dexcom G5")
    }

    // MARK: - Guards against the catalog drifting from its consumers

    /// Drift guard. Every kit still ships the vestigial `*Plugin/Info.plist` from upstream Loop, which declares
    /// its manager identifier. Trio never loads those bundles, but they are a reliable inventory of what is
    /// vendored, so a kit added without a catalog entry fails here instead of silently missing from the picker.
    ///
    /// Runtime discovery was tried and does not work: these managers are pure Swift classes, so
    /// `objc_copyClassNamesForImage` cannot see them, and the unscoped `objc_copyClassList` walk that sees more
    /// aborts the process on private Foundation classes.
    @Test("Every vendored driver is either catalogued or explicitly excluded") func testCatalogCoversVendoredDrivers() throws {
        let declared = try Self.vendoredManagerIdentifiers()
        #expect(!declared.pumps.isEmpty, "Found no pump plugin plists — did the repo layout change?")
        #expect(!declared.cgms.isEmpty, "Found no CGM plugin plists — did the repo layout change?")

        // Vendored but deliberately not offered in Trio.
        let excludedCGMs: Set<String> = [
            "DexShareClient", // Dexcom Share: no longer offered
            "G6SensorKit" // native G6 transport, not wired up in Trio
        ]

        let missingPumps = declared.pumps.subtracting(DeviceCatalog.pumps.map(\.id))
        #expect(missingPumps.isEmpty, "Vendored pumps absent from DeviceCatalog: \(missingPumps.sorted())")

        let missingCGMs = declared.cgms
            .subtracting(DeviceCatalog.cgmManagerEntries.map(\.id))
            .subtracting(excludedCGMs)
        #expect(missingCGMs.isEmpty, "Vendored CGMs absent from DeviceCatalog: \(missingCGMs.sorted())")
    }

    /// Reads `*/*Plugin/Info.plist` from the repo, located relative to this source file.
    private static func vendoredManagerIdentifiers() throws -> (pumps: Set<String>, cgms: Set<String>) {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TrioTests
            .deletingLastPathComponent() // repo root
        var pumps = Set<String>(), cgms = Set<String>()

        for kit in try FileManager.default.contentsOfDirectory(atPath: repoRoot.path) {
            let kitURL = repoRoot.appendingPathComponent(kit)
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: kitURL.path) else { continue }
            for child in children where child.hasSuffix("Plugin") {
                let plist = kitURL.appendingPathComponent(child).appendingPathComponent("Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let dict = try? PropertyListSerialization
                      .propertyList(from: data, format: nil) as? [String: Any]
                else { continue }
                if let id = dict["com.loopkit.Loop.PumpManagerIdentifier"] as? String { pumps.insert(id) }
                if let id = dict["com.loopkit.Loop.CGMManagerIdentifier"] as? String { cgms.insert(id) }
            }
        }
        return (pumps, cgms)
    }
}

@Suite("Device Icon Tests") struct DeviceIconTests {
    /// The whole point of resolving artwork from the kit bundles ourselves is that it costs no submodule
    /// changes. The cost is that asset names and bundle identifiers live in those submodules, so a bump can
    /// rename one and the picker would silently fall back to a glyph. These tests make that a red test.

    @Test("Every declared CGM icon actually resolves") func testCGMIconsResolve() {
        for entry in DeviceCatalog.cgms where entry.icon != .none {
            #expect(entry.iconImage != nil, "\(entry.name): \(entry.icon) did not resolve")
        }
    }

    @Test("Every declared pump icon actually resolves") func testPumpIconsResolve() {
        for entry in DeviceCatalog.pumps where entry.icon != .none {
            #expect(entry.iconImage != nil, "\(entry.name): \(entry.icon) did not resolve")
        }
    }

    @Test("Every referenced UI framework bundle is loadable") func testUIBundlesLoad() {
        let identifiers = (DeviceCatalog.cgms.map(\.icon) + DeviceCatalog.pumps.map(\.icon))
            .compactMap { icon -> String? in
                guard case let .uiBundle(identifier, _) = icon else { return nil }
                return identifier
            }
        #expect(!identifiers.isEmpty, "Expected at least one *UI framework icon")
        for identifier in Set(identifiers) {
            #expect(Bundle(identifier: identifier) != nil, "\(identifier) is not an embedded framework")
        }
    }

    @Test("Entries with no artwork fall back to a category glyph") func testGapsFallBack() {
        let gaps = DeviceCatalog.cgms.filter { $0.icon == .none && $0.isSelectableInPicker }
        #expect(!gaps.isEmpty, "Expected the known artwork gaps to still be present")
        for entry in gaps {
            #expect(entry.iconImage == nil)
            #expect(!entry.fallbackSymbolName.isEmpty, "\(entry.name) has no glyph to fall back to")
            #expect(
                UIImage(systemName: entry.fallbackSymbolName) != nil,
                "\(entry.fallbackSymbolName) is not a valid SF Symbol"
            )
        }
    }

    @Test("Known artwork gaps are exactly as documented") func testGapsAreAsDocumented() {
        let gapNames = Set(
            DeviceCatalog.cgms.filter { $0.icon == .none && $0.isSelectableInPicker }.map(\.name) +
                DeviceCatalog.pumps.filter { $0.icon == .none }.map(\.name)
        )
        // Libre 1/2/2+: LibreTransmitterUI ships no asset catalog. Libre 3: LibreLoopUI ships only onboarding
        // steps. G5: CGMBLEKitUI ships only "g6". xDrip4iOS and Enlite never had artwork.
        #expect(gapNames == [
            "FreeStyle Libre 1 / 2 / 2+",
            "FreeStyle Libre 3 / 3+ (Beta)",
            "Dexcom G5",
            "xDrip4iOS",
            "Medtronic Enlite"
        ])
    }
}

@Suite("Onboarding Pump Tests") struct OnboardingPumpTests {
    /// These values drive therapy setup, so they are pinned against the pre-catalog behaviour they replaced.

    @Test("Onboarding offers real pumps only") func testExcludesSimulator() {
        let offered = DeviceCatalog.onboardingPumps
        #expect(offered.count == DeviceCatalog.pumps.count - 1)
        #expect(!offered.contains { $0.manufacturer == .simulator })
    }

    @Test("Omnipod stays the onboarding fallback") func testFallbackIsOmnipod() {
        #expect(DeviceCatalog.defaultOnboardingPump.name == "Omnipod")
        // The old code fell back to the DASH bounds when nothing was selected.
        // Now the kit's own grid, which excludes 0 for Eros compatibility.
        let capability = DeviceCatalog.defaultOnboardingPump.basalCapability
        #expect(capability == BasalRateCapability(minimum: 0.05, maximum: 30, step: 0.05))
    }

    @Test("Basal bounds come from each kit's own declared grid") func testBasalBounds() {
        // Derived from each kit's declared grid, with 0 dropped because oref rejects a 0 basal rate.
        let expected: [String: BasalRateCapability] = [
            "Omnipod": BasalRateCapability(minimum: 0.05, maximum: 30, step: 0.05),
            "MiniMed": BasalRateCapability(minimum: 0.05, maximum: 35, step: 0.05),
            // Dana delivers in 0.01 steps; Trio previously offered 0.05.
            "Dana": BasalRateCapability(minimum: 0.01, maximum: 3, step: 0.01),
            "Medtrum Nano": BasalRateCapability(minimum: 0.05, maximum: 30, step: 0.05)
        ]
        for (name, capability) in expected {
            let entry = DeviceCatalog.pumps.first { $0.name == name }
            #expect(entry?.basalCapability == capability, "\(name): got \(String(describing: entry?.basalCapability))")
        }
    }

    @Test("Every onboarding basal grid is evenly spaced") func testGridsAreUniform() {
        // A single min/max/step picker can only represent a uniform grid. If a kit ever ships a banded onboarding
        // grid (MiniMed's paired gen-23 grid is banded 0.025/0.05/0.1), this fails instead of silently coarsening.
        let grids: [String: [Double]] = [
            "Omnipod": OmniPumpManager.onboardingSupportedBasalRates,
            "MiniMed": MinimedPumpManager.onboardingSupportedBasalRates,
            "Dana": DanaKitPumpManager.onboardingSupportedBasalRates,
            "Medtrum Nano": MedtrumPumpManager.onboardingSupportedBasalRates
        ]
        for (name, grid) in grids {
            #expect(BasalRateCapability.isUniform(grid), "\(name) onboarding grid is not evenly spaced")
        }
    }

    @Test("An upgrading user's paired pump is preselected") func testUpgradePreselection() {
        #expect(DeviceCatalog.onboardingPump(forPersistedIdentifier: "Minimed500").name == "MiniMed")
        #expect(DeviceCatalog.onboardingPump(forPersistedIdentifier: "Dana").name == "Dana")
        // Legacy identifiers from the retired OmniKit / OmniBLE managers.
        #expect(DeviceCatalog.onboardingPump(forPersistedIdentifier: "Omnipod-DASH").name == "Omnipod")
        // The simulator is catalogued but never offered in onboarding, so it must fall back rather than
        // preselecting an entry the picker has no row for.
        #expect(DeviceCatalog.onboardingPump(forPersistedIdentifier: "MockPumpManager").name == "Omnipod")
        #expect(DeviceCatalog.onboardingPump(forPersistedIdentifier: "NotAPump").name == "Omnipod")
    }

    @Test("Only tubed pumps report a rewind") func testRewindReporting() {
        // rewindResetsAutosens is only meaningful for pumps with a reservoir to rewind.
        let expected = ["Omnipod": false, "MiniMed": true, "Dana": true, "Medtrum Nano": false]
        for (name, reports) in expected {
            let entry = DeviceCatalog.pumps.first { $0.name == name }
            #expect(entry?.reportsRewindEvents == reports, "\(name) rewind behaviour changed")
        }
    }
}
