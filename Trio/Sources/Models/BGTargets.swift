import Foundation

public struct BGTargets: JSON {
    public var units: GlucoseUnits
    public var userPreferredUnits: GlucoseUnits
    public var targets: [BGTargetEntry]

    public init(units: GlucoseUnits, userPreferredUnits: GlucoseUnits, targets: [BGTargetEntry]) {
        self.units = units
        self.userPreferredUnits = userPreferredUnits
        self.targets = targets
    }
}

protocol BGTargetsObserver {
    func bgTargetsDidChange(_ bgTargets: BGTargets)
}

extension BGTargets {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case targets
    }
}

public struct BGTargetEntry: JSON {
    public let low: Decimal
    public let high: Decimal
    public let start: String
    public let offset: Int

    public init(low: Decimal, high: Decimal, start: String, offset: Int) {
        self.low = low
        self.high = high
        self.start = start
        self.offset = offset
    }
}

extension BGTargets {
    func currentTarget(at date: Date = Date()) -> Decimal? {
        let calendar = Calendar.current

        for (index, entry) in targets.enumerated() {
            guard let entryTime = TherapySettingsUtil.parseTime(entry.start) else {
                debug(.default, "Invalid BG target entry start time: \(entry.start)")
                continue
            }
            let components = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
            guard let start = calendar.date(
                bySettingHour: components.hour ?? 0,
                minute: components.minute ?? 0,
                second: components.second ?? 0,
                of: date
            ) else { continue }

            let end: Date
            if index < targets.count - 1, let nextTime = TherapySettingsUtil.parseTime(targets[index + 1].start) {
                let nextComponents = calendar.dateComponents([.hour, .minute, .second], from: nextTime)
                end = calendar.date(
                    bySettingHour: nextComponents.hour ?? 0,
                    minute: nextComponents.minute ?? 0,
                    second: nextComponents.second ?? 0,
                    of: date
                ) ?? start
            } else {
                end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            }

            if date >= start, date < end {
                return entry.low
            }
        }
        return nil
    }
}
