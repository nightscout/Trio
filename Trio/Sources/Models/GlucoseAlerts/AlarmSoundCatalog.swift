import Foundation

/// Catalog of the bundled critical-alarm sound files (`Trio/Resources/Sounds/`).
/// Ported from Loop's audio-critical-alerts branch. Single source of truth
/// for the alarm sound picker.
enum AlarmSoundCatalog {
    /// (filename, displayName) tuples in display order.
    private static let catalog: [(filename: String, displayName: String)] = [
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
        ("crying.caf", String(localized: "Crying"))
    ]

    static let allFilenames: [String] = catalog.map(\.filename)

    static func displayName(for filename: String) -> String {
        catalog.first { $0.filename == filename }?.displayName ?? filename
    }
}
