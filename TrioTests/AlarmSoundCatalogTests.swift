import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: alarm sound catalog") struct AlarmSoundCatalogTests {
    @Test("Every catalog filename is bundled at the main bundle root") func allBundled() {
        for filename in AlarmSoundCatalog.allFilenames {
            let resource = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            #expect(
                Bundle.main.url(forResource: resource, withExtension: ext) != nil,
                "\(filename) is missing from the bundle root"
            )
        }
    }

    @Test("Filenames are unique across the catalog") func noDuplicateFilenames() {
        let all = AlarmSoundCatalog.allFilenames
        #expect(Set(all).count == all.count)
    }

    @Test("Every glucose alarm gets Acoustic, Electronic and Voice") func glucoseThemedCoverage() {
        for type in GlucoseAlertType.allCases {
            let ids = AlarmSoundCatalog.themedEntries(for: .glucose(type)).map(\.id)
            #expect(ids.contains(where: { $0.hasPrefix("acoustic.") }), "no acoustic set for \(type)")
            #expect(ids.contains(where: { $0.hasPrefix("electronic.") }), "no electronic set for \(type)")
            #expect(ids.contains(where: { $0.hasPrefix("voice.") }), "no voice set for \(type)")
        }
    }

    @Test("Every device tier gets Acoustic, Electronic and Voice") func deviceThemedCoverage() {
        for tier in DeviceAlertSeverity.allCases {
            let ids = AlarmSoundCatalog.themedEntries(for: .deviceTier(tier)).map(\.id)
            #expect(ids.contains(where: { $0.hasPrefix("acoustic.") }), "no acoustic set for \(tier)")
            #expect(ids.contains(where: { $0.hasPrefix("electronic.") }), "no electronic set for \(tier)")
            #expect(ids.contains(where: { $0.hasPrefix("voice.") }), "no voice set for \(tier)")
        }
    }

    @Test("A themed set is offered only on the alarm it was written for") func themedSetsAreScoped() {
        let urgentLow = AlarmSoundCatalog.themedEntries(for: .glucose(.urgentLow)).map(\.id)
        #expect(urgentLow.contains("acoustic.ulg"))
        #expect(!urgentLow.contains("acoustic.hg"))
        let critical = AlarmSoundCatalog.themedEntries(for: .deviceTier(.critical)).map(\.id)
        #expect(critical.contains("acoustic.dcr"))
        #expect(!critical.contains("acoustic.dts"))
    }

    @Test("Urgency sets carry three levels, voice sets two") func optionCounts() {
        for entry in AlarmSoundCatalog.entries {
            switch entry.selector {
            case .urgency: #expect(entry.options.count == AlarmUrgencyLevel.allCases.count)
            case .voice: #expect(entry.options.count == AlarmVoice.allCases.count)
            case .none: #expect(entry.options.count == 1)
            }
        }
    }

    @Test("Defaults are Acoustic Medium everywhere") func defaultsAreAcousticMedium() {
        for type in GlucoseAlertType.allCases {
            let name = type.defaultSoundFilename
            #expect(name.hasPrefix("acoustic_"), "\(type) default is \(name)")
            #expect(name.hasSuffix("_medium.caf"), "\(type) default is \(name)")
        }
        for tier in DeviceAlertSeverity.allCases {
            let name = tier.defaultSoundFilename
            #expect(name.hasPrefix("acoustic_"), "\(tier) default is \(name)")
            #expect(name.hasSuffix("_medium.caf"), "\(tier) default is \(name)")
        }
    }

    @Test("Each alarm's default resolves back to its own themed entry") func defaultsResolveToOwnScope() {
        for type in GlucoseAlertType.allCases {
            let scope = AlarmSoundCatalog.Scope.glucose(type)
            let name = type.defaultSoundFilename
            #expect(AlarmSoundCatalog.themedEntries(for: scope).contains(where: { $0.filenames.contains(name) }))
        }
        for tier in DeviceAlertSeverity.allCases {
            let scope = AlarmSoundCatalog.Scope.deviceTier(tier)
            let name = tier.defaultSoundFilename
            #expect(AlarmSoundCatalog.themedEntries(for: scope).contains(where: { $0.filenames.contains(name) }))
        }
    }

    @Test("Generic tones are offered everywhere and stay out of the themed list") func genericTones() {
        let allGeneric = AlarmSoundCatalog.genericTones.allSatisfy { $0.isGeneric }
        #expect(allGeneric)
        #expect(AlarmSoundCatalog.genericTones.contains(where: { $0.id == "meow.caf" }))
        for type in GlucoseAlertType.allCases {
            let noneGeneric = AlarmSoundCatalog.themedEntries(for: .glucose(type)).allSatisfy { !$0.isGeneric }
            #expect(noneGeneric, "generic tone leaked into \(type) themed list")
        }
    }

    @Test("Legacy tone filenames still resolve, so stored picks survive") func legacyFilenamesResolve() {
        for legacy in ["urgent_low.caf", "high_chimes.caf", "bloop.caf", "trill.caf", "chime.caf", "bloom.caf"] {
            #expect(AlarmSoundCatalog.entry(forFilename: legacy) != nil, "\(legacy) no longer resolves")
        }
    }

    @Test("Display names name the variant for themed sets only") func displayNames() {
        #expect(AlarmSoundCatalog.displayName(for: "acoustic_ulg_medium.caf") == "Acoustic · Medium")
        #expect(AlarmSoundCatalog.displayName(for: "voice_ulg_amy.caf") == "Voice · Amy")
        #expect(AlarmSoundCatalog.displayName(for: "high_chimes.caf") == "High Chimes")
    }
}
