import CryptoKit
import Foundation

struct TherapyScheduleEntry: Equatable, Hashable, Sendable {
    let seconds: Int
    let value: Decimal
}

struct TherapyTargetEntry: Equatable, Hashable, Sendable {
    let seconds: Int
    let low: Decimal
    let high: Decimal
}

/// A named set of basal rates, carb ratios, insulin sensitivities and glucose targets. Glucose values are in mg/dL.
struct TrioTherapyProfile: Equatable, Identifiable, Sendable {
    var name: String
    let basal: [TherapyScheduleEntry]
    let carbRatio: [TherapyScheduleEntry]
    let sensitivity: [TherapyScheduleEntry]
    let target: [TherapyTargetEntry]

    /// Basal rates are kept at three decimal places, the precision of the pumps' rates and of the fingerprint. oref doses
    /// to the low target, so each target's high value is its low value.
    init(
        name: String,
        basal: [TherapyScheduleEntry],
        carbRatio: [TherapyScheduleEntry],
        sensitivity: [TherapyScheduleEntry],
        target: [TherapyTargetEntry]
    ) {
        self.name = name
        self.basal = basal.map { TherapyScheduleEntry(seconds: $0.seconds, value: $0.value.rounded(scale: 3)) }
        self.carbRatio = carbRatio
        self.sensitivity = sensitivity
        self.target = target.map { TherapyTargetEntry(seconds: $0.seconds, low: $0.low, high: $0.low) }
    }

    var id: String { name }

    static let defaultName = "Default"
    /// The Nightscout store key of the Default profile.
    static let defaultStoreKey = "default"

    var isDefault: Bool { name == Self.defaultName }

    var storeKey: String { isDefault ? Self.defaultStoreKey : name }

    func renamed(_ newName: String) -> TrioTherapyProfile {
        var copy = self
        copy.name = newName
        return copy
    }

    func hasSameValues(as other: TrioTherapyProfile) -> Bool {
        basal == other.basal && carbRatio == other.carbRatio && sensitivity == other.sensitivity && target == other.target
    }
}

// MARK: - Settings files

extension TrioTherapyProfile {
    init(
        name: String,
        basalProfile: [BasalProfileEntry],
        carbRatios: CarbRatios,
        insulinSensitivities: InsulinSensitivities,
        bgTargets: BGTargets
    ) {
        self.init(
            name: name,
            basal: basalProfile.map { TherapyScheduleEntry(seconds: $0.minutes * 60, value: $0.rate) },
            carbRatio: carbRatios.schedule.map { TherapyScheduleEntry(seconds: $0.offset * 60, value: $0.ratio) },
            sensitivity: insulinSensitivities.sensitivities
                .map { TherapyScheduleEntry(seconds: $0.offset * 60, value: $0.sensitivity) },
            target: bgTargets.targets.map { TherapyTargetEntry(seconds: $0.offset * 60, low: $0.low, high: $0.high) }
        )
    }

    static func startString(seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    var basalProfileEntries: [BasalProfileEntry] {
        basal.map { BasalProfileEntry(start: Self.startString(seconds: $0.seconds), minutes: $0.seconds / 60, rate: $0.value) }
    }

    var carbRatios: CarbRatios {
        CarbRatios(
            units: .grams,
            schedule: carbRatio.map {
                CarbRatioEntry(start: Self.startString(seconds: $0.seconds), offset: $0.seconds / 60, ratio: $0.value)
            }
        )
    }

    var insulinSensitivities: InsulinSensitivities {
        InsulinSensitivities(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            sensitivities: sensitivity.map {
                InsulinSensitivityEntry(
                    sensitivity: $0.value,
                    offset: $0.seconds / 60,
                    start: Self.startString(seconds: $0.seconds)
                )
            }
        )
    }

    var bgTargets: BGTargets {
        BGTargets(
            units: .mgdL,
            userPreferredUnits: .mgdL,
            targets: target.map {
                BGTargetEntry(low: $0.low, high: $0.high, start: Self.startString(seconds: $0.seconds), offset: $0.seconds / 60)
            }
        )
    }

    func replacing(
        basalProfile: [BasalProfileEntry]? = nil,
        carbRatios: CarbRatios? = nil,
        insulinSensitivities: InsulinSensitivities? = nil,
        bgTargets: BGTargets? = nil
    ) -> TrioTherapyProfile {
        TrioTherapyProfile(
            name: name,
            basalProfile: basalProfile ?? basalProfileEntries,
            carbRatios: carbRatios ?? self.carbRatios,
            insulinSensitivities: insulinSensitivities ?? self.insulinSensitivities,
            bgTargets: bgTargets ?? self.bgTargets
        )
    }
}

// MARK: - Fingerprint

extension TrioTherapyProfile {
    /// The canonical string of the values as a Nightscout store entry in `units` holds them.
    func fingerprintCanonicalString(units: GlucoseUnits) -> String {
        func glucose(_ value: Decimal) -> Decimal { units == .mmolL ? value.asMmolL : value }
        return Self.fingerprintCanonicalString(
            basal: basal.map { ($0.seconds, $0.value) },
            carbratio: carbRatio.map { ($0.seconds, $0.value) },
            sens: sensitivity.map { ($0.seconds, glucose($0.value)) },
            targetLow: target.map { ($0.seconds, glucose($0.low)) },
            targetHigh: target.map { ($0.seconds, glucose($0.high)) }
        )
    }

    static func fingerprintCanonicalString(
        basal: [(Int, Decimal)],
        carbratio: [(Int, Decimal)],
        sens: [(Int, Decimal)],
        targetLow: [(Int, Decimal)],
        targetHigh: [(Int, Decimal)]
    ) -> String {
        func section(_ name: String, _ values: [(Int, Decimal)]) -> String {
            let joined = values.map { seconds, value in
                "\(seconds):" + String(format: "%.3f", NSDecimalNumber(decimal: value).doubleValue)
            }.joined(separator: ",")
            return "\(name)=\(joined)"
        }
        return [
            section("basal", basal),
            section("carbratio", carbratio),
            section("sens", sens),
            section("target_low", targetLow),
            section("target_high", targetHigh)
        ].joined(separator: ";")
    }

    static func fingerprint(of canonicalString: String) -> String {
        let digest = SHA256.hash(data: Data(canonicalString.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// The first 16 hex characters of the SHA-256 of the canonical string, as Loop and LoopFollow compute it.
    func fingerprint(units: GlucoseUnits) -> String {
        Self.fingerprint(of: fingerprintCanonicalString(units: units))
    }

    /// Matches the values in mg/dL or mmol/L.
    func matchesFingerprint(_ fingerprint: String) -> Bool {
        let candidate = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return candidate == self.fingerprint(units: .mgdL) || candidate == self.fingerprint(units: .mmolL)
    }
}
