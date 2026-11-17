import Foundation

/// The therapy editors' value ranges, glucose in mg/dL.
enum TherapyProfileLimits {
    struct Range {
        let min: Decimal
        let max: Decimal
        let step: Decimal
    }

    static let carbRatio = Range(min: 1, max: 50, step: 0.1)
    static let sensitivity = Range(min: 9, max: 540, step: 1)
    static let target = Range(min: 72, max: 180, step: 1)
    static let maxSegments = 48
    static let segmentSeconds = 1800
    static let maxNameLength = 32
    /// The most profiles, Default included. Nightscout refuses a profile document much larger than this allows.
    static let maxProfiles = 20
}

struct TherapyBasalLimits: Equatable, Sendable {
    /// Nonzero rates the pump accepts.
    let supportedRates: [Decimal]
    let maxBasal: Decimal

    /// Supported rates up to max basal, ascending.
    var allowedRates: [Decimal] {
        supportedRates.filter { $0 > 0 && $0 <= maxBasal + Self.tolerance }.sorted()
    }

    static let tolerance: Decimal = 0.000001

    /// The basal editor's rates when no pump is connected.
    static let fallbackRates: [Decimal] = stride(from: 5.0, to: 1001.0, by: 5.0).map { ($0.decimal ?? .zero) / 100 }

    static let editorLimits = TherapyBasalLimits(supportedRates: fallbackRates, maxBasal: fallbackRates.last ?? 0)
}

enum TherapyProfileValidator {
    /// `existingNames` are the other profiles' names.
    static func validateName(_ rawName: String, existingNames: [String], isDefaultProfile: Bool = false) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name != rawName {
            return String(localized: "The name must not start or end with spaces.")
        }
        if name.isEmpty {
            return String(localized: "The name must not be empty.")
        }
        if name.count > TherapyProfileLimits.maxNameLength {
            return String(localized: "The name must be at most \(TherapyProfileLimits.maxNameLength) characters.")
        }
        if name.contains(".") {
            return String(localized: "The name must not contain a period.")
        }
        if name.hasPrefix("$") {
            return String(localized: "The name must not start with $.")
        }
        if !isDefaultProfile, name.caseInsensitiveCompare(TrioTherapyProfile.defaultName) == .orderedSame {
            return String(localized: "The name \(TrioTherapyProfile.defaultName) is reserved.")
        }
        if existingNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return String(localized: "A profile named \(name) already exists.")
        }
        return nil
    }

    /// The reason the profile is not acceptable, or nil.
    static func validate(_ profile: TrioTherapyProfile, basalLimits: TherapyBasalLimits) -> String? {
        let schedules = [
            (profile.basal.map(\.seconds), String(localized: "Basal Rates")),
            (profile.carbRatio.map(\.seconds), String(localized: "Carb Ratios")),
            (profile.sensitivity.map(\.seconds), String(localized: "Insulin Sensitivities")),
            (profile.target.map(\.seconds), String(localized: "Glucose Targets"))
        ]
        for (starts, label) in schedules {
            if let reason = validateSchedule(starts, label: label) {
                return reason
            }
        }

        let allowedRates = basalLimits.allowedRates
        for entry in profile.basal {
            let time = timeString(entry.seconds)
            let rate = entry.value.formatted()
            if entry.value <= 0 {
                return String(localized: "Basal rate at \(time) must be greater than 0 U/hr.")
            }
            if entry.value > basalLimits.maxBasal + TherapyBasalLimits.tolerance {
                return String(
                    localized: "Basal rate \(rate) U/hr at \(time) exceeds the max basal rate of \(basalLimits.maxBasal.formatted()) U/hr."
                )
            }
            if !allowedRates.contains(where: { abs($0 - entry.value) <= TherapyBasalLimits.tolerance }) {
                return String(localized: "Basal rate \(rate) U/hr at \(time) is not supported by the pump.")
            }
        }

        if let reason = validateValues(
            profile.carbRatio,
            range: TherapyProfileLimits.carbRatio,
            label: String(localized: "Carb Ratio")
        )
            ?? validateValues(profile.sensitivity, range: TherapyProfileLimits.sensitivity, label: String(localized: "ISF"))
        {
            return reason
        }
        return validateValues(
            profile.target.map { TherapyScheduleEntry(seconds: $0.seconds, value: $0.low) },
            range: TherapyProfileLimits.target,
            label: String(localized: "Target")
        )
    }

    static func validateSchedule(_ starts: [Int], label: String) -> String? {
        guard let first = starts.first else {
            return String(localized: "\(label): the schedule is empty.")
        }
        if first != 0 {
            return String(localized: "\(label): the schedule must start at midnight.")
        }
        if starts.count > TherapyProfileLimits.maxSegments {
            return String(localized: "\(label): the schedule has more than \(TherapyProfileLimits.maxSegments) entries.")
        }
        for (index, start) in starts.enumerated() {
            if start < 0 || start >= 86400 || start % TherapyProfileLimits.segmentSeconds != 0 {
                return String(localized: "\(label): start times must be on the hour or half hour.")
            }
            if index > 0, start <= starts[index - 1] {
                return String(localized: "\(label): start times must be in ascending order.")
            }
        }
        return nil
    }

    /// The reason the list of scheduled switches is not acceptable, or nil. Profile names are checked by the caller.
    static func validateScheduledSwitches(_ entries: [ScheduledProfileSwitch]) -> String? {
        if entries.count > ScheduledProfileSwitch.maxCount {
            return String(localized: "There can be at most \(ScheduledProfileSwitch.maxCount) scheduled switches.")
        }
        if Set(entries.map(\.id)).count != entries.count || entries.contains(where: \.id.isEmpty) {
            return String(localized: "Each scheduled switch needs its own id.")
        }
        var slots: Set<Int> = []
        for entry in entries {
            guard (1 ... 7).contains(entry.weekday) else {
                return String(localized: "The weekday of a scheduled switch must be 1 to 7.")
            }
            guard (0 ..< 86400).contains(entry.time), entry.time % 60 == 0 else {
                return String(localized: "The time of a scheduled switch must be a whole minute of the day.")
            }
            guard slots.insert(entry.weekday * 86400 + entry.time).inserted else {
                return String(
                    localized: "Two scheduled switches start on \(weekdayName(entry.weekday)) at \(timeString(entry.time))."
                )
            }
        }
        return nil
    }

    /// The weekday's name, Sunday = 1.
    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : String(weekday)
    }

    /// A schedule start time in the user's time format, the same on every day.
    static func timeString(_ seconds: Int) -> String {
        Date(timeIntervalSinceReferenceDate: TimeInterval(seconds))
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: .gmt))
    }

    private static func validateValues(
        _ entries: [TherapyScheduleEntry],
        range: TherapyProfileLimits.Range,
        label: String
    ) -> String? {
        for entry in entries {
            let time = timeString(entry.seconds)
            let value = entry.value.formatted()
            if entry.value < range.min || entry.value > range.max {
                return String(
                    localized: "\(label) \(value) at \(time) is outside \(range.min.formatted())–\(range.max.formatted())."
                )
            }
            if !isMultiple(entry.value - range.min, of: range.step) {
                return String(localized: "\(label) \(value) at \(time) is not a multiple of \(range.step.formatted()).")
            }
        }
        return nil
    }

    static func isMultiple(_ value: Decimal, of step: Decimal) -> Bool {
        let quotient = NSDecimalNumber(decimal: value / step)
        let rounded = quotient.rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        ))
        return abs(quotient.subtracting(rounded).decimalValue) < 0.000001
    }
}
