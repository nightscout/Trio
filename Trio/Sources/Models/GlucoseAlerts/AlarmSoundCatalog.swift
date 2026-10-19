import Foundation

/// How disruptive a themed alarm sounds. Intensity is carried by timbre,
/// loudness and length together — each level is its own recording, not one
/// recording at three gain settings.
enum AlarmUrgencyLevel: String, CaseIterable, Identifiable, Codable {
    case mild
    case medium
    case harsh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mild: return String(localized: "Mild")
        case .medium: return String(localized: "Medium")
        case .harsh: return String(localized: "Harsh")
        }
    }
}

/// Spoken alert voices.
enum AlarmVoice: String, CaseIterable, Identifiable {
    case amy
    case bryce

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amy: return String(localized: "Amy")
        case .bryce: return String(localized: "Bryce")
        }
    }
}

/// Catalog of the bundled alarm sound files (`Trio/Resources/Sounds/`).
/// Single source of truth for the alarm sound picker.
///
/// Themed sounds are written per alarm — the Urgent Low set is not the High
/// Glucose set at another pitch — so each is offered only on the alarm it was
/// written for and leads the list there. Everything else is a generic tone,
/// offered everywhere, tucked under "Other Sounds".
///
/// The stored value stays a plain filename, so the selected variant is
/// recovered by looking the filename back up and nothing needs migrating.
enum AlarmSoundCatalog {
    /// Which alarm a sound is offered on.
    enum Scope: Equatable {
        case glucose(GlucoseAlertType)
        case deviceTier(DeviceAlertSeverity)
    }

    /// What the picker reveals once a themed entry is selected.
    enum Selector: Equatable {
        case none
        case urgency
        case voice
    }

    struct Option: Identifiable, Equatable {
        let id: String
        let displayName: String
        let filename: String
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let displayName: String
        /// Empty means generic: offered on every alarm, under "Other Sounds".
        let scopes: [Scope]
        let selector: Selector
        let options: [Option]

        var isGeneric: Bool { scopes.isEmpty }
        var filenames: [String] { options.map(\.filename) }

        func option(forFilename filename: String) -> Option? {
            options.first { $0.filename == filename }
        }

        /// Middle of the urgency slider, and the set the designer recommends
        /// after hallway testing with PWDs and caregivers.
        var defaultOption: Option {
            options.first { $0.id == AlarmUrgencyLevel.medium.rawValue } ?? options[0]
        }
    }

    // MARK: - Themed sets

    /// Filename slug per alarm, matching the sound designer's prefixes.
    private static let slugs: [(slug: String, scopes: [Scope])] = [
        ("ulg", [.glucose(.urgentLow)]),
        ("lg", [.glucose(.low)]),
        ("lgs", [.glucose(.forecastedLow)]),
        ("hg", [.glucose(.high)]),
        ("cr", [.glucose(.carbsRequired)]),
        ("dcr", [.deviceTier(.critical)]),
        // No set was written for the Normal tier, so it shares the
        // Time-Sensitive one, the gentler of the two device sets.
        ("dts", [.deviceTier(.timeSensitive), .deviceTier(.normal)])
    ]

    private static func themed(_ theme: String, _ displayName: String) -> [Entry] {
        slugs.map { slug, scopes in
            Entry(
                id: "\(theme).\(slug)",
                displayName: displayName,
                scopes: scopes,
                selector: .urgency,
                options: AlarmUrgencyLevel.allCases.map {
                    Option(
                        id: $0.rawValue,
                        displayName: $0.displayName,
                        filename: "\(theme)_\(slug)_\($0.rawValue).caf"
                    )
                }
            )
        }
    }

    private static let voiceEntries: [Entry] = slugs.map { slug, scopes in
        Entry(
            id: "voice.\(slug)",
            displayName: String(localized: "Voice"),
            scopes: scopes,
            selector: .voice,
            options: AlarmVoice.allCases.map {
                Option(id: $0.rawValue, displayName: $0.displayName, filename: "voice_\(slug)_\($0.rawValue).caf")
            }
        )
    }

    // MARK: - Generic tones

    private static let genericEntries: [Entry] = [
        ("urgent_low.caf", String(localized: "Urgent Low")),
        ("critical.caf", String(localized: "Critical")),
        ("alarm.caf", String(localized: "Alarm")),
        ("bright_alarm.caf", String(localized: "Bright Alarm")),
        ("honk.caf", String(localized: "Honk")),
        ("trill.caf", String(localized: "Trill")),
        ("chime.caf", String(localized: "Chime")),
        ("clear_chimes.caf", String(localized: "Clear Chimes")),
        ("high_chimes.caf", String(localized: "High Chimes")),
        ("dings.caf", String(localized: "Dings")),
        ("bloom.caf", String(localized: "Bloom")),
        ("bloop.caf", String(localized: "Bloop")),
        ("spring.caf", String(localized: "Spring")),
        ("minimal.caf", String(localized: "Minimal")),
        ("simple.caf", String(localized: "Simple")),
        ("synth.caf", String(localized: "Synth")),
        ("mood_synth.caf", String(localized: "Mood Synth")),
        ("crying.caf", String(localized: "Crying")),
        ("glass_bell.caf", String(localized: "Glass Bell")),
        ("harp.caf", String(localized: "Harp")),
        ("meow.caf", String(localized: "Meow")),
        ("saw_wave.caf", String(localized: "Saw Wave")),
        ("hard_saw_wave.caf", String(localized: "Hard Saw Wave")),
        ("sine_wave.caf", String(localized: "Sine Wave")),
        ("open_can.caf", String(localized: "Open Can")),
        ("open_wrapper.caf", String(localized: "Open Wrapper"))
    ].map { filename, name in
        Entry(
            id: filename,
            displayName: name,
            scopes: [],
            selector: .none,
            options: [Option(id: "default", displayName: name, filename: filename)]
        )
    }

    // MARK: - Lookup

    static let entries: [Entry] = themed("acoustic", String(localized: "Acoustic"))
        + themed("electronic", String(localized: "Electronic"))
        + voiceEntries
        + genericEntries

    static let allFilenames: [String] = entries.flatMap(\.filenames)

    /// Themed sets written for this alarm, in display order.
    static func themedEntries(for scope: Scope) -> [Entry] {
        entries.filter { $0.scopes.contains(scope) }
    }

    /// Generic tones, offered on every alarm.
    static var genericTones: [Entry] { genericEntries }

    static func entry(forFilename filename: String) -> Entry? {
        entries.first { $0.filenames.contains(filename) }
    }

    /// The themed default for an alarm: Acoustic, Medium.
    static func defaultFilename(for scope: Scope) -> String? {
        themedEntries(for: scope).first { $0.id.hasPrefix("acoustic.") }?.defaultOption.filename
    }

    static func displayName(for filename: String) -> String {
        guard let entry = entry(forFilename: filename) else { return filename }
        guard entry.selector != .none, let option = entry.option(forFilename: filename) else {
            return entry.displayName
        }
        return "\(entry.displayName) · \(option.displayName)"
    }
}
